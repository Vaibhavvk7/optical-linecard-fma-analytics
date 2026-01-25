import io
import re
import pandas as pd
import streamlit as st

st.set_page_config(page_title="Nokia FMA Linecard Analytics", layout="wide")
st.title("Optical Line Card FMA — Failure Trends & Root Cause Drivers")


# -----------------------------
# Helpers
# -----------------------------
def read_clean_csv(path: str, header="infer", names=None, **kwargs) -> pd.DataFrame:
    """
    Read a CSV but drop sqlcmd noise lines if they sneak in.
    Supports both headered and headerless CSVs via `header` and `names`.
    """
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        lines = [
            ln for ln in f.readlines()
            if "Changed database context" not in ln
            and "(rows affected)" not in ln
            and not ln.strip().startswith("Msg ")
            and ln.strip() != ""
        ]
    return pd.read_csv(io.StringIO("".join(lines)), header=header, names=names, **kwargs)


def read_two_numbers_csv(path: str):
    """
    Reads a file and extracts the first line that looks like: number,number
    Returns (float, int).
    """
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if re.match(r"^[0-9.]+,[0-9]+$", line):
                a, b = line.split(",")
                return float(a), int(b)
    raise ValueError(f"No valid 'number,number' line found in {path}")


# -----------------------------
# Load files (robust to headerless + noise)
# -----------------------------
pass_rate, total_runs = read_two_numbers_csv("outputs/pbi_exec_overview.csv")

# Pareto is currently headerless: failure_code, fail_count
pareto = read_clean_csv(
    "outputs/pbi_failure_pareto.csv",
    header=None,
    names=["failure_code", "fail_count"],
)

# Weekly trend often headerless: build_week_start, test_runs, fails, fail_rate_pct
trend = read_clean_csv(
    "outputs/pbi_weekly_trend.csv",
    header=None,
    names=["build_week_start", "test_runs", "fails", "fail_rate_pct"],
)

# Vendor/lot returns often headerless:
lot = read_clean_csv(
    "outputs/pbi_vendor_lot_returns.csv",
    header=None,
    names=[
        "optic_vendor",
        "lot_code",
        "units_built",
        "units_returned",
        "field_return_rate_pct",
        "nff_count",
    ],
)

# Analytics outputs
rca_global = read_clean_csv("outputs/rca_scorecard.csv")  # usually has headers already
rca_mode = read_clean_csv("outputs/rca_by_failure_mode.csv", header=None, names=[
    "failure_code",
    "driver",
    "n_present",
    "fail_rate_present",
    "n_absent",
    "fail_rate_absent",
    "lift_ratio",
])


# -----------------------------
# KPI cards
# -----------------------------
c1, c2, c3, c4 = st.columns(4)
c1.metric("Pass Rate (%)", f"{pass_rate:.2f}")
c2.metric("Total Test Runs", f"{total_runs:,}")
c3.metric("Field Returns", f"{550:,}")   # from your DB counts
c4.metric("Units Built", f"{10000:,}")   # from your DB counts

st.divider()


# -----------------------------
# Pilot ramp trend
# -----------------------------
st.subheader("Pilot Ramp: Weekly Failure Rate")

# Your SQL output looks like: 2024-12-30 00:00:00.000
trend["build_week_start"] = pd.to_datetime(
    trend["build_week_start"],
    format="%Y-%m-%d %H:%M:%S.%f",
    errors="coerce",
)
trend["fail_rate_pct"] = pd.to_numeric(trend["fail_rate_pct"], errors="coerce")
trend = trend.dropna(subset=["build_week_start", "fail_rate_pct"]).sort_values("build_week_start")

st.line_chart(trend.set_index("build_week_start")["fail_rate_pct"])

colA, colB = st.columns(2)

with colA:
    st.subheader("Failure Pareto (Lab)")
    pareto_plot = pareto.copy()
    pareto_plot["fail_count"] = pd.to_numeric(pareto_plot["fail_count"], errors="coerce")
    pareto_plot = pareto_plot.dropna(subset=["failure_code", "fail_count"]).sort_values("fail_count", ascending=False)
    st.bar_chart(pareto_plot.set_index("failure_code")["fail_count"])

with colB:
    st.subheader("Top Supplier Lots by Field Return Rate")
    lot_plot = lot.copy()
    lot_plot["field_return_rate_pct"] = pd.to_numeric(lot_plot["field_return_rate_pct"], errors="coerce")
    lot_plot = lot_plot.dropna(subset=["optic_vendor", "lot_code", "field_return_rate_pct"])
    lot_plot = lot_plot.sort_values("field_return_rate_pct", ascending=False)
    st.dataframe(lot_plot.head(15), use_container_width=True)

st.divider()


# -----------------------------
# RCA
# -----------------------------
st.subheader("Root Cause Drivers (Lift Ratios)")
col1, col2 = st.columns(2)

with col1:
    st.caption("Global drivers (all failures)")
    if "driver" in rca_global.columns and "lift_ratio" in rca_global.columns:
        tmp = rca_global[["driver", "lift_ratio"]].copy()
        tmp["lift_ratio"] = pd.to_numeric(tmp["lift_ratio"], errors="coerce")
        tmp = tmp.dropna().sort_values("lift_ratio", ascending=False)
        st.bar_chart(tmp.set_index("driver")["lift_ratio"])
    else:
        st.dataframe(rca_global.head(20), use_container_width=True)

with col2:
    st.caption("Per failure mode (select a mode)")
    # Convert numeric columns safely
    for col in ["n_present", "fail_rate_present", "n_absent", "fail_rate_absent", "lift_ratio"]:
        rca_mode[col] = pd.to_numeric(rca_mode[col], errors="coerce")
    rca_mode = rca_mode.dropna(subset=["failure_code", "driver", "lift_ratio"])

    modes = sorted(rca_mode["failure_code"].unique())
    default_mode = "THERMAL_DRIFT" if "THERMAL_DRIFT" in modes else modes[0]
    mode = st.selectbox("Failure mode", modes, index=modes.index(default_mode))

    mode_df = rca_mode[rca_mode["failure_code"] == mode].sort_values("lift_ratio", ascending=False)
    st.dataframe(mode_df, use_container_width=True)

st.info(
    "Lift > 1 means the driver increases the probability of that failure mode. "
    "Use this to prioritize corrective actions (thermal margin, PI/ripple, station calibration, supplier lots)."
)
