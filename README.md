# Optical Line Card Failure Mode Analytics & Root Cause Detection

**SQL Server • Python • Streamlit • Reliability Engineering**

---

## Overview

This project implements an **end-to-end Failure Mode Analysis (FMA) platform** for optical line cards, integrating manufacturing builds, lab test data, environmental telemetry, and field returns to identify failure trends and probable root causes during pilot ramp and production.

The system mirrors how **hardware reliability, manufacturing, and test engineering teams** investigate yield loss, false failures, and customer-impacting defects in large-scale networking hardware programs.

---

## Problem Statement

During pilot ramp and early production, optical line cards exhibit failures across multiple dimensions:

- **Lab test stations** (ICT, functional, burn-in, optical)
- **Environmental stress conditions** (temperature, voltage ripple)
- **Supplier-specific optic component lots**
- **Firmware and calibration drift**

Key analytical challenges include:

- Distinguishing **false lab failures vs. real field failures**
- Quantifying which factors **materially increase failure risk**
- Providing **data-backed root cause ranking** to guide engineering action

---

## What This Project Builds

### 1️⃣ Manufacturing & Test Data Platform (SQL Server)

A **normalized relational schema** designed to reflect real manufacturing systems, capturing:

- Product configuration (line card family, HW/FW revisions)
- Unit-level manufacturing history
- High-volume lab test results (**200k+ test runs**)
- Burn-in telemetry
- Field returns and RMA outcomes

Designed explicitly for **realistic joins, KPI queries, RCA workflows, and interview discussion**.

---

### 2️⃣ Analytical & Reliability Modeling (Python)

Python-based analytics perform:

- Failure rate and yield analysis
- Statistical **lift analysis** for root-cause drivers
- Lab vs. field confirmation analysis
- **Weibull survival modeling** for time-to-failure
- Logistic modeling for **driver explainability**

Focus is on **interpretability and engineering decision support**, not black-box ML.

---

### 3️⃣ Executive & Engineering Dashboard (Streamlit)

An interactive **Streamlit dashboard** presents:

- Executive quality KPIs
- Pilot ramp weekly failure trends
- Failure Pareto (lab)
- Supplier lot field-return impact
- Root cause driver ranking (global + per failure mode)

Built for **both leadership visibility and engineering deep dives**.

---

## Data Scale

| Metric                     | Volume   |
|---------------------------|----------|
| Units built               | 10,000   |
| Test runs                 | 200,000  |
| Burn-in telemetry rows    | 50,000   |
| Field returns             | 550      |
| Test stations             | 12       |
| Supplier lots             | 25       |

---

## Key Findings

### 🔹 Pilot Ramp Quality

- Overall pass rate: **98.05%**
- Failure rate stabilized during ramp with clear **inflection points tied to configuration and environment changes**

---

### 🔹 Lab Failure Pareto

Top lab failure modes identified:

- `STATION_FALSE_FAIL`
- `OPTICS_DEGRADATION`
- `FW_REGRESSION`
- `THERMAL_DRIFT`
- `VOLTAGE_RIPPLE`

---

### 🔹 Root Cause Driver Quantification (Lift Ratios)

**Global drivers (all failures):**

- High temperature: **2.26×**
- High voltage ripple: **1.90×**
- Station calibration drift: **1.67×**
- Optic vendor (OptiCore): **1.20×**

**Per-failure-mode examples:**

| Failure Mode          | Driver              | Lift  |
|----------------------|---------------------|-------|
| THERMAL_DRIFT        | High temperature    | 29.3× |
| VOLTAGE_RIPPLE       | High ripple         | 25.4× |
| STATION_FALSE_FAIL   | Drift station       | 14.9× |
| OPTICS_DEGRADATION   | Optic vendor lot    | 7.4×  |

This clearly separates **environment-driven**, **process-driven**, and **supplier-driven** issues.

---

### 🔹 Lab vs. Field Alignment

- Station false failures show **zero field confirmation**
- Environment-driven failures correlate strongly with **field returns**
- Certain optic vendor lots show elevated **customer impact despite passing lab tests**

---

## Dashboard Preview

📊 The Streamlit dashboard includes:

- Executive quality KPIs
- Pilot ramp weekly trends
- Failure Pareto analysis
- Supplier lot field return table
- Root cause driver ranking (global + per failure mode)

📁 Screenshots available in:
/dashboards/streamlit_screenshots


---

## Repository Structure

nokia-fma-linecard-analytics/
│
├── data_gen/
│   └── generate_data.py        # Synthetic data generator
│
├── sql/
│   ├── schema.sql              # SQL Server schema
│   ├── load.sql                # Data load scripts
│   ├── kpi_queries.sql         # KPI queries
│   ├── rca_queries.sql         # Root cause SQL
│   └── rca_by_failure_mode.sql
│
├── analytics/
│   └── rca_weibull.py          # Weibull + driver modeling
│
├── dashboards/
│   ├── app.py                  # Streamlit dashboard
│   └── streamlit_screenshots/
│
├── outputs/
│   └── *.csv                   # Analytics exports
│
├── notebooks/
│   ├── 01_eda_failure_trends.ipynb
│   ├── 02_stats_root_cause.ipynb
│   └── 03_weibull_survival.ipynb
│
└── README.md




---

## Technologies Used

- **SQL Server** (Docker, Linux)
- **Python**: pandas, numpy, scipy, scikit-learn
- **Streamlit**
- **Statistical Reliability Modeling** (Weibull)
- **Manufacturing & Test Analytics**

---

## Why This Matters

This project reflects **real-world hardware reliability analytics**, not toy datasets:

- Manufacturing-scale data volumes
- Cross-domain joins (manufacturing + test + field)
- Quantified, explainable root-cause insights
- Stakeholder-ready visualizations

It directly mirrors the analytical workflow used by **hardware reliability, test engineering, and manufacturing quality teams** in large networking and semiconductor organizations.

---

## Next Steps

- Integrate real telemetry ingestion
- Add automated anomaly detection on burn-in signals
- Extend with cost-of-quality modeling

---

## Author

**Vaibhav Kejriwal**  
M.S. Electrical & Computer Engineering  
Northeastern University
