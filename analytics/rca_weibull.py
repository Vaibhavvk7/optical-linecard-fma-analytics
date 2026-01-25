import os
import math
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

from scipy.stats import weibull_min
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score, classification_report

import pymssql  # pure-python friendly in Docker


SQL = {
    "returns_ttf": """
        USE NokiaFMA;

        SELECT
            u.unit_serial,
            u.build_date,
            fr.return_date,
            fr.repair_action,
            fr.confirmed_failure_mode
        FROM dbo.Dim_Unit u
        JOIN dbo.Fact_FieldReturn fr
          ON fr.unit_serial = u.unit_serial
        WHERE fr.repair_action <> 'NFF';
    """,
    "model_base": """
        USE NokiaFMA;

        SELECT TOP (200000)
            tr.pass_fail,
            tr.temp_c,
            tr.ripple_mv,
            tr.ber,
            tr.q_factor,
            tr.eye_height_mv,
            tr.rx_power_dbm,
            s.calibration_date,
            sl.optic_vendor,
            tr.test_type
        FROM dbo.Fact_TestRun tr
        JOIN dbo.Dim_Unit u ON u.unit_serial = tr.unit_serial
        JOIN dbo.Dim_Station s ON s.station_id = tr.station_id
        JOIN dbo.Dim_SupplierLot sl ON sl.supplier_lot_id = u.supplier_lot_id
        WHERE tr.temp_c IS NOT NULL AND tr.ripple_mv IS NOT NULL
          AND tr.ber IS NOT NULL AND tr.q_factor IS NOT NULL
          AND tr.eye_height_mv IS NOT NULL AND tr.rx_power_dbm IS NOT NULL;
    """,
    "rca_scorecard": """
        USE NokiaFMA;

        WITH base AS (
          SELECT
            tr.pass_fail,
            CASE WHEN tr.temp_c >= 75 THEN 1 ELSE 0 END AS high_temp,
            CASE WHEN tr.ripple_mv >= 35 THEN 1 ELSE 0 END AS high_ripple,
            CASE WHEN sl.optic_vendor = 'OptiCore' THEN 1 ELSE 0 END AS opti_vendor,
            CASE WHEN s.calibration_date < '2024-02-01' THEN 1 ELSE 0 END AS drift_station
          FROM dbo.Fact_TestRun tr
          JOIN dbo.Dim_Unit u ON u.unit_serial = tr.unit_serial
          JOIN dbo.Dim_SupplierLot sl ON sl.supplier_lot_id = u.supplier_lot_id
          JOIN dbo.Dim_Station s ON s.station_id = tr.station_id
        ),
        agg AS (
          SELECT
            SUM(CASE WHEN high_temp=1 THEN 1 ELSE 0 END) AS n_high_temp,
            SUM(CASE WHEN high_temp=1 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_high_temp,
            SUM(CASE WHEN high_temp=0 THEN 1 ELSE 0 END) AS n_low_temp,
            SUM(CASE WHEN high_temp=0 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_low_temp,

            SUM(CASE WHEN high_ripple=1 THEN 1 ELSE 0 END) AS n_high_ripple,
            SUM(CASE WHEN high_ripple=1 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_high_ripple,
            SUM(CASE WHEN high_ripple=0 THEN 1 ELSE 0 END) AS n_low_ripple,
            SUM(CASE WHEN high_ripple=0 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_low_ripple,

            SUM(CASE WHEN opti_vendor=1 THEN 1 ELSE 0 END) AS n_opti,
            SUM(CASE WHEN opti_vendor=1 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_opti,
            SUM(CASE WHEN opti_vendor=0 THEN 1 ELSE 0 END) AS n_nonopti,
            SUM(CASE WHEN opti_vendor=0 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_nonopti,

            SUM(CASE WHEN drift_station=1 THEN 1 ELSE 0 END) AS n_drift,
            SUM(CASE WHEN drift_station=1 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_drift,
            SUM(CASE WHEN drift_station=0 THEN 1 ELSE 0 END) AS n_nondrift,
            SUM(CASE WHEN drift_station=0 AND pass_fail=0 THEN 1 ELSE 0 END) AS f_nondrift
          FROM base
        )
        SELECT
          driver,
          fail_present,
          fail_absent,
          (fail_present / NULLIF(fail_absent,0)) AS lift_ratio
        FROM (
          SELECT 'HIGH_TEMP' AS driver,
                 (1.0 * f_high_temp / NULLIF(n_high_temp,0)) AS fail_present,
                 (1.0 * f_low_temp  / NULLIF(n_low_temp,0))  AS fail_absent
          FROM agg
          UNION ALL
          SELECT 'HIGH_RIPPLE',
                 (1.0 * f_high_ripple / NULLIF(n_high_ripple,0)),
                 (1.0 * f_low_ripple  / NULLIF(n_low_ripple,0))
          FROM agg
          UNION ALL
          SELECT 'DRIFT_STATION',
                 (1.0 * f_drift / NULLIF(n_drift,0)),
                 (1.0 * f_nondrift / NULLIF(n_nondrift,0))
          FROM agg
          UNION ALL
          SELECT 'OPTIC_VENDOR_OPTICORE',
                 (1.0 * f_opti / NULLIF(n_opti,0)),
                 (1.0 * f_nonopti / NULLIF(n_nonopti,0))
          FROM agg
        ) x
        ORDER BY lift_ratio DESC;
    """
}


def connect():
    # From a Docker container on Mac, connect to host-mapped port 1433:
    host = os.getenv("SQL_HOST", "host.docker.internal")
    user = os.getenv("SQL_USER", "sa")
    pwd  = os.getenv("SQL_PASSWORD", "Str0ng!Passw0rd123")
    port = int(os.getenv("SQL_PORT", "1433"))
    return pymssql.connect(server=host, user=user, password=pwd, port=port, database="master")


def fetch_df(conn, query: str) -> pd.DataFrame:
    return pd.read_sql(query, conn)


def weibull_time_to_failure(df_returns: pd.DataFrame, out_dir: str):
    df = df_returns.copy()
    df["build_date"] = pd.to_datetime(df["build_date"])
    df["return_date"] = pd.to_datetime(df["return_date"])
    df["ttf_days"] = (df["return_date"] - df["build_date"]).dt.days
    df = df[df["ttf_days"] > 0]

    # Fit Weibull (2-parameter, location fixed at 0)
    data = df["ttf_days"].values.astype(float)
    c, loc, scale = weibull_min.fit(data, floc=0)

    # Plot empirical CDF vs fitted CDF
    xs = np.linspace(data.min(), data.max(), 200)
    fitted_cdf = weibull_min.cdf(xs, c, loc=0, scale=scale)

    # empirical CDF
    sorted_data = np.sort(data)
    ecdf = np.arange(1, len(sorted_data) + 1) / len(sorted_data)

    plt.figure()
    plt.plot(sorted_data, ecdf, marker=".", linestyle="none", alpha=0.6)
    plt.plot(xs, fitted_cdf)
    plt.xlabel("Time-to-Failure (days)")
    plt.ylabel("CDF")
    plt.title(f"Weibull Fit (shape={c:.2f}, scale={scale:.1f})")
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "weibull_cdf.png"), dpi=160)
    plt.close()

    summary = pd.DataFrame([{
        "n_returns_used": int(len(df)),
        "weibull_shape_k": float(c),
        "weibull_scale_lambda_days": float(scale),
        "median_ttf_days": float(weibull_min.median(c, loc=0, scale=scale)),
        "p10_ttf_days": float(weibull_min.ppf(0.10, c, loc=0, scale=scale)),
        "p90_ttf_days": float(weibull_min.ppf(0.90, c, loc=0, scale=scale)),
    }])
    summary.to_csv(os.path.join(out_dir, "weibull_summary.csv"), index=False)
    df[["unit_serial", "ttf_days", "confirmed_failure_mode"]].to_csv(
        os.path.join(out_dir, "returns_ttf.csv"), index=False
    )
    return summary


def driver_model(df_base: pd.DataFrame, out_dir: str):
    df = df_base.copy()

    # target: fail=1
    df["y_fail"] = (df["pass_fail"] == 0).astype(int)

    # engineer features
    df["high_temp"] = (df["temp_c"] >= 75).astype(int)
    df["high_ripple"] = (df["ripple_mv"] >= 35).astype(int)
    df["drift_station"] = (pd.to_datetime(df["calibration_date"]) < pd.Timestamp("2024-02-01")).astype(int)
    df["opti_vendor"] = (df["optic_vendor"] == "OptiCore").astype(int)

    # basic numeric features (log BER helps)
    df["log10_ber"] = np.log10(df["ber"].clip(lower=1e-12))

    # one-hot for test_type
    test_dummies = pd.get_dummies(df["test_type"], prefix="test")
    X = pd.concat([
        df[["temp_c","ripple_mv","q_factor","eye_height_mv","rx_power_dbm","log10_ber",
            "high_temp","high_ripple","drift_station","opti_vendor"]],
        test_dummies
    ], axis=1)

    y = df["y_fail"].values

    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.25, random_state=42, stratify=y)

    # Logistic regression (interpretable, Nokia-friendly)
    model = LogisticRegression(max_iter=2000, n_jobs=1)
    model.fit(X_train, y_train)

    proba = model.predict_proba(X_test)[:, 1]
    auc = roc_auc_score(y_test, proba)

    # Coefficients -> importance
    coefs = pd.DataFrame({
        "feature": X.columns,
        "coef": model.coef_[0]
    }).sort_values("coef", ascending=False)

    coefs.to_csv(os.path.join(out_dir, "logreg_feature_coeffs.csv"), index=False)

    # Simple bar plot (top +/- features)
    top_pos = coefs.head(10)
    top_neg = coefs.tail(10)

    plot_df = pd.concat([top_pos, top_neg], axis=0)
    plt.figure(figsize=(10, 6))
    plt.barh(plot_df["feature"], plot_df["coef"])
    plt.xlabel("Logistic Regression Coefficient")
    plt.title(f"Failure Driver Model (AUC={auc:.3f})")
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "logreg_feature_coeffs.png"), dpi=160)
    plt.close()

    # Save a short text report
    with open(os.path.join(out_dir, "model_report.txt"), "w") as f:
        f.write(f"AUC: {auc:.4f}\n\n")
        f.write("Top positive drivers:\n")
        f.write(top_pos.to_string(index=False))
        f.write("\n\nTop negative drivers:\n")
        f.write(top_neg.to_string(index=False))
        f.write("\n\nClassification report (threshold=0.5):\n")
        f.write(classification_report(y_test, (proba >= 0.5).astype(int)))

    return auc, coefs


def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "outputs")
    os.makedirs(out_dir, exist_ok=True)

    conn = connect()

    # Weibull
    df_returns = fetch_df(conn, SQL["returns_ttf"])
    weibull_summary = weibull_time_to_failure(df_returns, out_dir)

    # Driver model
    df_base = fetch_df(conn, SQL["model_base"])
    auc, coefs = driver_model(df_base, out_dir)

    # RCA scorecard
    rca = fetch_df(conn, SQL["rca_scorecard"])
    rca.to_csv(os.path.join(out_dir, "rca_scorecard.csv"), index=False)

    print("✅ Outputs written to /outputs")
    print("Weibull summary:\n", weibull_summary.to_string(index=False))
    print(f"Driver model AUC: {auc:.3f}")
    print("\nRCA scorecard:\n", rca.to_string(index=False))


if __name__ == "__main__":
    main()

