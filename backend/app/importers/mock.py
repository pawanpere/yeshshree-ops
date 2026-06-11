"""Mock/config data the SAP exports don't carry — pilot scope, from the app map +
plan decisions. Real names, illustrative numbers; replaced by real config in the
admin screens during pilot setup. (Plan §1 decision 4: MVP runs on these + real exports.)"""

LINES = ["Front Body", "Side Panel LH", "Side Panel RH", "Floor Top"]

# App map: lines pre-mapped to SAP production orders (§5.14.2 step 1)
PRODUCTION_ORDERS = {
    "Front Body": "100482",
    "Side Panel LH": "100483",
    "Side Panel RH": "100484",
    "Floor Top": "100485",
}

CUSTOMERS = [{"sap_code": "5000", "name": "Bajaj Auto Ltd", "gstin": None}]

REJECT_REASONS = [  # app map §5.11 config — label_en, label_mr
    ("DENT", "Dent & Damage", "पोचा व नुकसान"),
    ("CO2_WELD", "CO₂ welding defect (undercut / blow hole)", "CO₂ वेल्डिंग दोष"),
    ("BOLT_MISS", "Knob mounting bolt missing", "बोल्ट गहाळ"),
    ("HOLE_MISMATCH", "Front panel hole mismatch", "छिद्र जुळत नाही"),
    ("SPOT_MISS", "Spot missing", "स्पॉट गहाळ"),
    ("WRINKLE", "Front body wrinkle", "सुरकुती"),
]

DOWNTIME_REASONS = [
    ("DIE_CHANGE", "Die change", "डाय बदल"),
    ("POWER", "Power", "वीज"),
    ("MAT_SHORT", "Material shortage", "मटेरियल कमतरता"),
    ("MAN_SHORT", "Manpower shortage", "मनुष्यबळ कमतरता"),
    ("BREAKDOWN", "Breakdown", "बिघाड"),
]

SPLITS = [  # family, yesh_pct, laxmi_pct — app map config screen, effective 01 Jun 2026
    ("RE Petrol", 74, 26),
    ("RE CNG", 20, 80),
    ("RE Diesel", 100, 0),
    ("EV GOGO", 0, 100),
]

MILLS = [  # name, lead_days, moq_mt, sourcing
    ("JSW", 14, 25, "multi"),
    ("TATA", 12, 25, "multi"),
    ("POSH", 10, 10, "single"),
]

TOLERANCES = [  # mat_group, uom, pct — steel by weight (Failure Scenarios #11)
    ("1103", "KG", "0.5"),
]

APP_SETTINGS = {
    "ops_mode": {"mode": "parallel_run"},
    "anomaly_thresholds": {"hard_qty_multiple": 5, "soft_deviation_pct": 20,
                           "rejection_spike_factor": 2.0},
    "debit_note": {"multiplier": 5},
    "gr_target_minutes": {"minutes": 30},
}

# One user per role — DEV CREDENTIALS ONLY (password == pin == "demo1234" hashed at seed).
# Pilot onboarding replaces these via the admin screen.
USERS = [
    # username, full_name, role, station, language
    ("admin", "Admin", "admin", None, "en"),
    ("md", "Managing Director", "management", None, "en"),
    ("planner", "Planning Head", "planning", None, "en"),
    ("gate1", "Gate Guard A", "plant_ops", "gate", "mr"),
    ("qc1", "QC Inspector A", "plant_ops", "qc", "mr"),
    ("store1", "Store Keeper A", "plant_ops", "store", "mr"),
    ("ppc1", "PPC Operator", "plant_ops", "ppc", "en"),
    ("sup1", "R. Sodhi", "supervisor", None, "mr"),
]

# Mock credit/qty limits for vendors that appear in the real GRN report.
# Values illustrative (app map shows ₹14L-style limits); confirmed at pilot setup.
DEFAULT_VENDOR_LIMITS = {"credit_limit": "1400000.00", "qty_limit_mt": "10.0"}
