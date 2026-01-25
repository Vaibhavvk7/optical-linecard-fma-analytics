import csv
import os
import random
from datetime import datetime, timedelta, date

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "data")

# ------------ Config (tweak these) ------------
SEED = 42
N_LINECARDS = 6
N_SUPPLIER_LOTS = 25
N_STATIONS = 12
N_UNITS = 10000
N_TESTRUNS = 200000
N_FIELD_RETURNS = 550
N_TELEMETRY_POINTS = 50000  # total burn-in telemetry rows

START_BUILD_DATE = date(2025, 1, 1)
END_BUILD_DATE   = date(2025, 4, 30)

# Failure pattern knobs
THERMAL_TEMP_C = 78.0
RIPPLE_MV = 40.0
BAD_OPTIC_VENDOR = "OptiCore"
BAD_LOT_FRACTION = 0.18
STATION_DRIFT_FRACTION = 0.15  # stations with overdue calibration => more NFF
FW_REGRESSION = "2.1.0"
FW_REGRESSION_FAIL_BOOST = 0.010

# ---------------------------------------------

def rand_date(d0: date, d1: date) -> date:
    delta = (d1 - d0).days
    return d0 + timedelta(days=random.randint(0, delta))

def rand_ts_around(d: date) -> datetime:
    # timestamp around that day
    base = datetime(d.year, d.month, d.day, 8, 0, 0)
    return base + timedelta(minutes=random.randint(0, 10*60))

def clamp(x, lo, hi):
    return max(lo, min(hi, x))

def write_csv(path, header, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)

def main():
    random.seed(SEED)
    os.makedirs(OUT_DIR, exist_ok=True)

    # ---- Dim_LineCard ----
    product_families = ["PHOTON-X", "AURORA", "NOVA"]
    hw_revs = ["A0", "A1", "B0"]
    fw_versions = ["2.0.3", "2.0.7", FW_REGRESSION, "2.1.3"]
    optics_types = ["SR", "LR", "ER"]
    data_rates = [100, 400]

    linecards = []
    for _ in range(N_LINECARDS):
        linecards.append([
            random.choice(product_families),
            random.choice(hw_revs),
            random.choice(fw_versions),
            random.choice(optics_types),
            random.choice(data_rates)
        ])
    write_csv(os.path.join(OUT_DIR, "dim_linecard.csv"),
              ["product_family","hw_revision","fw_version","optics_type","data_rate_gbps"],
              linecards)

    # ---- Dim_SupplierLot ----
    optic_vendors = ["OptiCore", "LumaNet", "PhotonWorks", "ZenOptics"]
    pcb_vendors = ["PCBWorks", "CircuMax", "BoardSmith"]
    countries = ["USA", "Germany", "Japan", "India", "Taiwan"]

    supplier_lots = []
    bad_lot_ids = set()
    for i in range(N_SUPPLIER_LOTS):
        ov = random.choice(optic_vendors)
        # force some bad lots tied to BAD_OPTIC_VENDOR
        if random.random() < BAD_LOT_FRACTION:
            ov = BAD_OPTIC_VENDOR
            bad_lot_ids.add(i+1)  # lot id will be identity starting at 1 after load
        lot_code = f"LOT-{ov[:3].upper()}-{random.randint(1000,9999)}"
        lot_date = rand_date(date(2024, 11, 1), date(2025, 3, 15)).isoformat()
        supplier_lots.append([ov, random.choice(pcb_vendors), lot_code, lot_date, random.choice(countries)])
    write_csv(os.path.join(OUT_DIR, "dim_supplier_lot.csv"),
              ["optic_vendor","pcb_vendor","lot_code","lot_date","country"],
              supplier_lots)

    # ---- Dim_Station ----
    station_types = ["ICT","FUNCTIONAL","BURNIN","OPTICAL"]
    stations = []
    drift_station_ids = set()
    for i in range(N_STATIONS):
        stype = random.choice(station_types)
        name = f"STN-{stype[:3]}-{i+1:02d}"
        # some stations have old calibration dates (drift)
        if random.random() < STATION_DRIFT_FRACTION:
            cal = rand_date(date(2023, 1, 1), date(2024, 1, 1))
            drift_station_ids.add(i+1)
        else:
            cal = rand_date(date(2024, 10, 1), date(2025, 3, 1))
        stations.append([name, stype, cal.isoformat(), random.choice(["MA", "PA", "TX"])])
    write_csv(os.path.join(OUT_DIR, "dim_station.csv"),
              ["station_name","station_type","calibration_date","site"],
              stations)

    # ---- Dim_Unit ----
    units = []
    # store attributes to drive failures later
    unit_meta = {}
    for i in range(N_UNITS):
        serial = f"LC-{i+1:06d}"
        linecard_id = random.randint(1, N_LINECARDS)
        supplier_lot_id = random.randint(1, N_SUPPLIER_LOTS)
        site = random.choice(["Allentown-PA", "Dallas-TX", "Lowell-MA"])
        operator = f"OP-{random.randint(100,999)}"
        build = rand_date(START_BUILD_DATE, END_BUILD_DATE)

        units.append([serial, linecard_id, supplier_lot_id, site, operator, build.isoformat()])

        # capture properties
        # derive fw_version and hw_revision by linecard_id AFTER load? We'll approximate here by random weights
        unit_meta[serial] = {
            "linecard_id": linecard_id,
            "supplier_lot_id": supplier_lot_id,
            "build_date": build,
            "bad_lot": supplier_lot_id in bad_lot_ids
        }

    write_csv(os.path.join(OUT_DIR, "dim_unit.csv"),
              ["unit_serial","linecard_id","supplier_lot_id","manufacturing_site","operator_id","build_date"],
              units)

    # ---- Fact_TestRun ----
    test_types = ["ICT","FUNCTIONAL","BURNIN","OPTICAL"]
    failure_codes = ["THERMAL_DRIFT","VOLTAGE_RIPPLE","OPTICS_DEGRADATION","STATION_FALSE_FAIL","FW_REGRESSION","UNKNOWN"]

    testruns = []
    # pick a subset of units that tend to run hot/ripple to create real patterns
    hot_units = set(random.sample(list(unit_meta.keys()), k=int(N_UNITS*0.10)))
    ripple_units = set(random.sample(list(unit_meta.keys()), k=int(N_UNITS*0.08)))
    fw_units = set(random.sample(list(unit_meta.keys()), k=int(N_UNITS*0.12)))  # impacted by FW regression

    for _ in range(N_TESTRUNS):
        serial = f"LC-{random.randint(1, N_UNITS):06d}"
        m = unit_meta[serial]
        build = m["build_date"]

        station_id = random.randint(1, N_STATIONS)
        test_type = random.choice(test_types)
        start = rand_ts_around(build + timedelta(days=random.randint(0, 10)))
        end = start + timedelta(minutes=random.randint(2, 25))

        # baseline metrics
        temp = random.gauss(55, 8)
        ripple = abs(random.gauss(18, 7))
        vcore = random.gauss(0.92, 0.02)
        vaux = random.gauss(1.80, 0.04)
        iin = abs(random.gauss(2.2, 0.7))

        # optical metrics
        ber = max(1e-12, 10 ** random.uniform(-12, -8))  # 1e-12 to 1e-8
        q = random.gauss(9.5, 1.0)
        eye_h = random.gauss(320, 50)
        eye_w = random.gauss(80, 12)
        rxp = random.gauss(-6.5, 1.8)
        txp = random.gauss(-2.0, 1.0)
        hum = clamp(random.gauss(35, 12), 5, 85)

        # inject patterns
        p_fail = 0.012  # baseline failure rate

        # thermal drift
        if serial in hot_units and test_type in ("BURNIN","OPTICAL"):
            temp = random.gauss(THERMAL_TEMP_C, 3.5)
            ber *= 10 ** random.uniform(1.0, 2.2)
            q -= random.uniform(1.0, 2.0)
            eye_h -= random.uniform(60, 120)
            p_fail += 0.030

        # voltage ripple
        if serial in ripple_units and test_type in ("FUNCTIONAL","OPTICAL"):
            ripple = random.gauss(RIPPLE_MV, 6.0)
            eye_h -= random.uniform(40, 90)
            ber *= 10 ** random.uniform(0.7, 1.8)
            p_fail += 0.022

        # optics vendor lot issue
        if m["bad_lot"] and test_type in ("OPTICAL","BURNIN"):
            q -= random.uniform(0.8, 1.6)
            rxp -= random.uniform(0.5, 1.5)
            p_fail += 0.020

        # station drift false fails (esp. ICT/FUNCTIONAL)
        if station_id in drift_station_ids and test_type in ("ICT","FUNCTIONAL"):
            p_fail += 0.020

        # firmware regression
        if serial in fw_units and test_type in ("OPTICAL","FUNCTIONAL"):
            # intermittent BER spikes
            ber *= 10 ** random.uniform(0.5, 1.3)
            p_fail += FW_REGRESSION_FAIL_BOOST

        # decide fail
        pass_fail = 1 if random.random() > p_fail else 0

        failure_code = ""
        if pass_fail == 0:
            # choose a plausible failure code
            candidates = []
            if temp >= 75: candidates.append("THERMAL_DRIFT")
            if ripple >= 35: candidates.append("VOLTAGE_RIPPLE")
            if m["bad_lot"]: candidates.append("OPTICS_DEGRADATION")
            if station_id in drift_station_ids: candidates.append("STATION_FALSE_FAIL")
            if serial in fw_units: candidates.append("FW_REGRESSION")
            failure_code = random.choice(candidates if candidates else failure_codes)

        testruns.append([
            serial, station_id, test_type,
            start.isoformat(sep=" "), end.isoformat(sep=" "),
            pass_fail, failure_code if failure_code else None,
            ber, q, eye_h, eye_w, rxp, txp,
            vcore, vaux, iin, ripple,
            temp, hum
        ])

    write_csv(os.path.join(OUT_DIR, "fact_testrun.csv"),
              ["unit_serial","station_id","test_type","start_ts","end_ts","pass_fail","failure_code",
               "ber","q_factor","eye_height_mv","eye_width_ps","rx_power_dbm","tx_power_dbm",
               "vcore_v","vaux_v","iin_a","ripple_mv","temp_c","humidity_pct"],
              testruns)

    # ---- Fact_FieldReturn ----
    # Sample returns more likely from bad_lot/hot/ripple units; add NFF due to drift stations.
    returns = []
    all_serials = list(unit_meta.keys())
    # weight sampling
    weights = []
    for s in all_serials:
        w = 1.0
        if unit_meta[s]["bad_lot"]: w += 2.2
        if s in hot_units: w += 1.4
        if s in ripple_units: w += 1.2
        weights.append(w)

    def weighted_choice():
        r = random.random() * sum(weights)
        acc = 0.0
        for s, w in zip(all_serials, weights):
            acc += w
            if acc >= r:
                return s
        return all_serials[-1]

    symptom_map = {
        "THERMAL_DRIFT": "INTERMITTENT_LINK_DROP",
        "VOLTAGE_RIPPLE": "BOOT_FAILURE",
        "OPTICS_DEGRADATION": "HIGH_BER_ALARM",
        "FW_REGRESSION": "CRC_ERRORS",
        "STATION_FALSE_FAIL": "NO_SYMPTOM_REPRO",
        "UNKNOWN": "UNSTABLE_THROUGHPUT"
    }

    for _ in range(N_FIELD_RETURNS):
        serial = weighted_choice()
        build = unit_meta[serial]["build_date"]
        ret_date = build + timedelta(days=random.randint(10, 120))

        # determine likely confirmed mode
        mode_candidates = []
        if serial in hot_units: mode_candidates.append("THERMAL_DRIFT")
        if serial in ripple_units: mode_candidates.append("VOLTAGE_RIPPLE")
        if unit_meta[serial]["bad_lot"]: mode_candidates.append("OPTICS_DEGRADATION")
        if serial in fw_units: mode_candidates.append("FW_REGRESSION")

        confirmed = random.choice(mode_candidates) if mode_candidates else "UNKNOWN"

        # some NFF returns (especially to reflect station false fail / repro issue)
        if random.random() < 0.18:
            repair = "NFF"
            confirmed_out = None
            symptom = "NO_SYMPTOM_REPRO"
        else:
            repair = random.choice(["REWORK","REPLACE"])
            confirmed_out = confirmed
            symptom = symptom_map.get(confirmed, "UNSTABLE_THROUGHPUT")

        returns.append([serial, ret_date.isoformat(), symptom, confirmed_out, repair, None])

    write_csv(os.path.join(OUT_DIR, "fact_fieldreturn.csv"),
              ["unit_serial","return_date","symptom_code","confirmed_failure_mode","repair_action","notes"],
              returns)

    # ---- Fact_BurnInTelemetry (optional, but great for interviews) ----
    telemetry = []
    # focus telemetry on hot + bad_lot units
    focus_units = list(set(list(hot_units)[:int(N_UNITS*0.05)]) | set([s for s in all_serials if unit_meta[s]["bad_lot"]][:int(N_UNITS*0.03)]))
    if not focus_units:
        focus_units = random.sample(all_serials, k=max(50, int(N_UNITS*0.02)))

    for _ in range(N_TELEMETRY_POINTS):
        serial = random.choice(focus_units)
        build = unit_meta[serial]["build_date"]
        ts = rand_ts_around(build + timedelta(days=random.randint(0, 7))) + timedelta(minutes=random.randint(0, 12*60))

        temp = random.gauss(62, 7)
        ripple = abs(random.gauss(20, 8))
        vcore = random.gauss(0.92, 0.02)
        ber = max(1e-12, 10 ** random.uniform(-12, -9))

        if serial in hot_units:
            temp = random.gauss(THERMAL_TEMP_C, 3.0)
            ber *= 10 ** random.uniform(0.8, 1.8)
        if unit_meta[serial]["bad_lot"]:
            ber *= 10 ** random.uniform(0.3, 1.1)
        if serial in ripple_units:
            ripple = random.gauss(RIPPLE_MV, 5.0)

        telemetry.append([serial, ts.isoformat(sep=" "), temp, vcore, ripple, ber])

    write_csv(os.path.join(OUT_DIR, "fact_burnin_telemetry.csv"),
              ["unit_serial","ts","temp_c","vcore_v","ripple_mv","ber_snapshot"],
              telemetry)

    print(f"✅ Wrote CSVs to: {os.path.abspath(OUT_DIR)}")
    print("Files:")
    for fn in [
        "dim_linecard.csv","dim_supplier_lot.csv","dim_station.csv","dim_unit.csv",
        "fact_testrun.csv","fact_fieldreturn.csv","fact_burnin_telemetry.csv"
    ]:
        print(" -", fn)

if __name__ == "__main__":
    main()

