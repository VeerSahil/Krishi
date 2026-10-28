"""Explicit operational care classes. No invented ML training labels or agronomic certification."""
from datetime import datetime, timezone
from copy import deepcopy

CLASS_NAMES = {"A": "Routine follow-up", "B": "One check needed", "C": "Multiple checks needed", "U": "Needs verification"}

def assess_care(readings, policy):
    warnings = []
    blocking = []
    demo = policy.get("basis") == "demo_rules"
    if demo: warnings.append("Demonstration policy: these bands are examples, not validated crop-specific care limits.")
    if readings.get("temperatureSource") == "simulated": warnings.append("Temperature is simulated, not measured.")
    if readings.get("nutrientSource") != "soil_test": warnings.append("Nutrient values were entered manually; no soil-test source was declared.")
    if readings.get("nutrientUnit", "unknown") != policy.get("nutrientUnit", "unknown"):
        blocking.append("Nutrient units do not match the selected policy. No unit conversion was performed.")
    if readings.get("moistureUnit", "unknown") != policy.get("moistureUnit"):
        blocking.append("Moisture basis does not match the policy. Relative moisture is not volumetric water content.")
    if readings.get("nutrientUnit", "unknown") == "unknown": warnings.append("Nutrient units are unspecified.")
    if demo:
        warnings.extend(blocking)
        blocking = []  # Demo-only classes may illustrate raw input bands, always visibly labelled.
    findings = []
    for key, band in policy["ranges"].items():
        value = readings.get(key)
        if value is None:
            blocking.append(f"Missing {key} reading.")
            continue
        if value < band["low"] or value > band["high"]:
            findings.append({"key": key, "value": value, "low": band["low"], "high": band["high"],
                             "direction": "low" if value < band["low"] else "high"})
    grade = "U" if blocking else "C" if len(findings) >= 2 else "B" if findings else "A"
    return {"grade": grade, "label": CLASS_NAMES[grade], "findings": findings,
            "warnings": warnings + blocking, "demonstrationOnly": demo or readings.get("temperatureSource") == "simulated",
            "method": "count_of_readings_outside_configured_bands", "policy": deepcopy(policy),
            "notADiagnosis": True, "assessedAt": datetime.now(timezone.utc)}

TEXT = {
 "en": {"check": "Ask our team to recheck {name} (recorded: {value}{unit}).", "manual": "Nutrient readings were entered manually; confirm them against a soil test.", "units": "Nutrient units were not specified; ask the team to confirm them.", "title": "Your farm visit report", "summary": "Our team visited your field. Care class {grade}: {label}.",
        "next": "Discuss the flagged readings with the field team before changing irrigation or nutrient use.",
        "routine": "Keep a dated record of field conditions and arrange the next check with our team.",
        "unknown": "Ask the team to verify the reading units and measurement sources before acting on this report.",
        "demo": "This is a demonstration assessment. It does not establish crop health or prescribe treatment.",
        "simulated": "The temperature used in this report was simulated, not measured.",
        "disclaimer": "Care classes organise follow-up work; they are not a diagnosis or a yield guarantee."},
 "hi": {"check": "हमारी टीम से {name} दोबारा जांचने को कहें (दर्ज मान: {value}{unit})।", "manual": "पोषक तत्वों के मान हाथ से दर्ज किए गए हैं; मिट्टी की जांच से इनकी पुष्टि करें।", "units": "पोषक तत्वों की इकाई नहीं बताई गई है; टीम से इसकी पुष्टि करें।", "title": "आपके खेत की निरीक्षण रिपोर्ट", "summary": "हमारी टीम ने आपके खेत का निरीक्षण किया। देखभाल श्रेणी {grade}: {label}।",
        "next": "सिंचाई या पोषक तत्वों का उपयोग बदलने से पहले चिह्नित रीडिंग पर टीम से चर्चा करें।",
        "routine": "खेत की स्थिति का दिनांक सहित रिकॉर्ड रखें और अगली जांच का समय टीम से तय करें।",
        "unknown": "इस रिपोर्ट पर कार्रवाई से पहले टीम से माप की इकाइयों और स्रोतों की पुष्टि करवाएं।",
        "demo": "यह प्रात्यक्षिक आकलन है। यह फसल के स्वास्थ्य या उपचार की पुष्टि नहीं करता।",
        "simulated": "इस रिपोर्ट का तापमान सिम्युलेटेड है, मापा नहीं गया है।",
        "disclaimer": "ये श्रेणियां आगे की जांच व्यवस्थित करती हैं; यह निदान या उपज की गारंटी नहीं है।"},
 "mr": {"check": "आमच्या पथकाला {name} पुन्हा तपासण्यास सांगा (नोंद: {value}{unit}).", "manual": "अन्नद्रव्यांच्या नोंदी हाताने भरल्या आहेत; माती परीक्षणातून त्यांची खात्री करा.", "units": "अन्नद्रव्यांचे एकक दिलेले नाही; पथकाकडून खात्री करून घ्या.", "title": "तुमच्या शेतभेटीचा अहवाल", "summary": "आमच्या पथकाने तुमच्या शेताला भेट दिली. देखभाल श्रेणी {grade}: {label}.",
        "next": "सिंचन किंवा पोषकद्रव्यांचा वापर बदलण्यापूर्वी नोंदवलेल्या मोजमापांबाबत पथकाशी चर्चा करा.",
        "routine": "शेताच्या स्थितीची दिनांकासह नोंद ठेवा आणि पुढील तपासणीची वेळ पथकाशी ठरवा.",
        "unknown": "या अहवालावर कृती करण्यापूर्वी मोजमापाची एकके व स्रोत पथकाकडून पडताळून घ्या.",
        "demo": "हे प्रात्यक्षिक मूल्यमापन आहे. यातून पिकाचे आरोग्य किंवा उपचार निश्चित होत नाहीत.",
        "simulated": "या अहवालातील तापमान अनुकरण केलेले आहे, मोजलेले नाही.",
        "disclaimer": "या श्रेणी पुढील तपासणी ठरवण्यासाठी आहेत; हे निदान किंवा उत्पादनाची हमी नाही."},
}
LABELS = {"en": CLASS_NAMES,
 "hi": {"A": "नियमित देखभाल", "B": "एक जांच जरूरी", "C": "कई जांच जरूरी", "U": "पुष्टि जरूरी"},
 "mr": {"A": "नियमित देखभाल", "B": "एक तपासणी आवश्यक", "C": "अनेक तपासण्या आवश्यक", "U": "पडताळणी आवश्यक"}}

READING_LABELS = {
 "en": {"moisture": "moisture", "temperature": "temperature", "nitrogen": "nitrogen (N)", "potassium": "potassium (K)"},
 "hi": {"moisture": "नमी", "temperature": "तापमान", "nitrogen": "नाइट्रोजन (N)", "potassium": "पोटैशियम (K)"},
 "mr": {"moisture": "ओलावा", "temperature": "तापमान", "nitrogen": "नत्र (N)", "potassium": "पालाश (K)"},
}

def report_template(survey, draft, language="en"):
    text = TEXT[language]
    assessment = draft["careAssessment"]
    grade = assessment["grade"]
    notices = [text["disclaimer"]]
    if assessment["demonstrationOnly"]: notices.append(text["demo"])
    if draft.get("temperatureSource") == "simulated": notices.append(text["simulated"])
    if survey.get("nutrientSource") != "soil_test": notices.append(text["manual"])
    if survey.get("nutrientUnit", "unknown") == "unknown": notices.append(text["units"])
    actions = [text["unknown"] if grade == "U" else text["routine"] if grade == "A" else text["next"]]
    if grade in ("B", "C"):
        for finding in assessment.get("findings", []):
            key = finding["key"]
            unit = "%" if key == "moisture" else " °C" if key == "temperature" else " " + survey.get("nutrientUnit", "unknown") if survey.get("nutrientUnit", "unknown") != "unknown" else ""
            actions.append(text["check"].format(name=READING_LABELS[language][key], value=finding["value"], unit=unit))
    return {"title": text["title"], "language": language,
            "summary": text["summary"].format(grade=grade, label=LABELS[language][grade]),
            "actions": actions,
            "notices": notices, "careClass": grade, "careLabel": LABELS[language][grade],
            "farmName": survey.get("farmName"), "submissionId": draft["submissionId"],
            "readings": {key: survey.get(key) for key in ("moisture", "moistureUnit", "temperature", "temperatureSource", "nitrogen", "phosphorus", "potassium", "nutrientUnit")}}
