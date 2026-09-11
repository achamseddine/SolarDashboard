#!/usr/bin/env python3
"""Builds assets/data/schools.json from the MEHE/UNICEF workbooks.

Usage:  python3 scripts/build_school_dataset.py <dir-with-xlsx> [out.json]

Expected workbooks (matched by substring of the file name):
  Overview_of_Public_Schools.xlsx     sheet "Public Schools"      – master list (CERD, names, caza, coordinates, enrolment)
  Connectivity534Schools.xlsx         sheet "Sheet1"              – schools with internet connectivity
  Public_Schools_Solar_Implementation sheets "Solarized Schools", "Contractors"
  Energy_Breakdown.xlsx               "Sheet1" equipment inventory, "Sheet2" annual load by category (kWh/year)
  EDU_Dashboard_Data.xlsx             attendance / risk sheets + "School List" (AM CERD ↔ PM CERD)

Personal data (director names, mobile numbers) is deliberately NOT exported:
the JSON is bundled inside the app and the repository is public.
"""
import glob
import json
import os
import re
import sys
from collections import OrderedDict, Counter

import openpyxl

SRC = sys.argv[1] if len(sys.argv) > 1 else '.'
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), '..', 'assets', 'data', 'schools.json')

# Caza names as used by the master list → geoBoundaries ADM2 names used by the app.
CAZA = {
    'El Minieh-Dennie': 'Minieh-Dinnieh', 'Miniyeh-Danniyeh': 'Minieh-Dinnieh', 'El Nabatieh': 'Nabatiye',
    'El Meten': 'El Metn', 'Bent Jbeil': 'Bent Jbail', 'Kesrwane': 'Kesrouan', 'El Koura': 'Koura',
    'Jbeil': 'Jbail', 'El Hermel': 'Hermel', 'El Batroun': 'Batroun',
}
# geoBoundaries ADM2 → app governorate (must match LebanonRegions.districtToRegion).
DISTRICT_TO_REGION = {
    'Beirut': 'Beirut', 'Baabda': 'Mount Lebanon', 'Aley': 'Mount Lebanon', 'Chouf': 'Mount Lebanon', 'El Metn': 'Mount Lebanon',
    'Kesrouan': 'Keserwan-Jbeil', 'Jbail': 'Keserwan-Jbeil',
    'Tripoli': 'North', 'Koura': 'North', 'Zgharta': 'North', 'Bcharre': 'North', 'Batroun': 'North', 'Minieh-Dinnieh': 'North',
    'Akkar': 'Akkar', 'Baalbek': 'Baalbek-Hermel', 'Hermel': 'Baalbek-Hermel',
    'Zahle': 'Bekaa', 'West Bekaa': 'Bekaa', 'Rachaya': 'Bekaa',
    'Saida': 'South', 'Sour': 'South', 'Jezzine': 'South',
    'Nabatiye': 'Nabatieh', 'Hasbaya': 'Nabatieh', 'Marjaayoun': 'Nabatieh', 'Bent Jbail': 'Nabatieh',
}
# Governorate spellings found in the secondary workbooks → app governorate.
GOV = {
    'beirut': 'Beirut', 'mount lebanon': 'Mount Lebanon', 'north': 'North', 'akkar': 'Akkar', 'south': 'South',
    'nabatieh': 'Nabatieh', 'beqaa': 'Bekaa', 'bekaa': 'Bekaa', 'baalbak - hermel': 'Baalbek-Hermel',
    'baalbek-el hermel': 'Baalbek-Hermel', 'baalback-hermel': 'Baalbek-Hermel', 'aley': 'Mount Lebanon',
    'chouf': 'Mount Lebanon', 'baabda': 'Mount Lebanon', 'jbeil': 'Keserwan-Jbeil', 'minnieh-dannieh': 'North',
    'zgharta': 'North', 'tyre': 'South',
}


def wb(name):
    files = glob.glob(os.path.join(SRC, f'*{name}*.xlsx'))
    if not files:
        sys.exit(f'missing workbook *{name}*.xlsx in {SRC}')
    return openpyxl.load_workbook(files[0], read_only=True, data_only=True)


def rows(ws, header_row=0):
    hdr = None
    for i, r in enumerate(ws.iter_rows(values_only=True)):
        if i < header_row:
            continue
        if hdr is None:
            hdr = [str(h).strip() if h is not None else '' for h in r]
            continue
        if all(v is None or (isinstance(v, str) and not v.strip()) for v in r):
            continue
        yield hdr, r


def clean(v):
    if v is None:
        return None
    if isinstance(v, str):
        s = v.replace('\xa0', ' ').strip()
        return s if s and s not in ('-', '#N/A', 'NA', 'N/A') else None
    return v


def num(v):
    v = clean(v)
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    try:
        return float(str(v).replace(',', ''))
    except ValueError:
        return None


def intval(v):
    n = num(v)
    return int(n) if n is not None else None


def cerd(v):
    n = num(v)
    return int(n) if n is not None and n > 0 else None


def text(v):
    v = clean(v)
    return re.sub(r'\s+', ' ', str(v)).strip() if v is not None else None


def yes(v):
    t = text(v)
    return None if t is None else t.lower() in ('yes', 'y', 'true', '1')


def risk(v):
    t = text(v)
    if not t:
        return None
    t = t.lower()
    if 'high' in t:
        return 'high'
    if 'medium' in t:
        return 'medium'
    if 'low' in t:
        return 'low'
    return None


schools = OrderedDict()


def school(c):
    if c not in schools:
        schools[c] = OrderedDict(cerd=c, inMaster=False)
    return schools[c]


# ------------------------------------------------------------ master list
for hdr, r in rows(wb('Overview_of_Public')['Public Schools']):
    c = cerd(r[0])
    if c is None:
        continue
    s = school(c)
    caza_raw = text(r[2])
    caza = CAZA.get(caza_raw, caza_raw)
    region = DISTRICT_TO_REGION.get(caza) or GOV.get((text(r[1]) or '').lower())
    s.update(
        inMaster=True,
        name=text(r[6]),
        nameAr=text(r[7]),
        region=region,
        caza=caza,
        cadaster=text(r[4]),
        casCode=intval(r[5]),
        ownership=text(r[3]),
        capacity=intval(r[8]),
        lat=num(r[9]),
        lng=num(r[10]),
        address=' – '.join(x for x in (text(r[11]), text(r[12])) if x) or None,
        phone=text(r[15]),
        studentsAm=intval(r[17]),
        studentsPm=intval(r[18]),
        enrollment=intval(r[19]),
    )

# ---------------------------------------------------------- connectivity
for hdr, r in rows(wb('Connectivity534')['Sheet1']):
    c = cerd(r[0])
    if c is None:
        continue
    s = school(c)
    s['connected'] = True
    s.setdefault('nameAr', text(r[1]))
    if not s.get('nameAr'):
        s['nameAr'] = text(r[1])
    if not s.get('region'):
        s['region'] = GOV.get((text(r[2]) or '').lower())
    if s.get('lat') is None and num(r[4]) is not None:
        s['lat'], s['lng'] = num(r[4]), num(r[5])

# ---------------------------------------------------- solar implementation
solar_wb = wb('Solar_Implementation')
contractors = {}
for hdr, r in rows(solar_wb['Contractors']):
    c = cerd(r[0])
    if c is None:
        continue
    contractors[c] = (text(r[4]), text(r[5]))


def solar_status(raw):
    t = (raw or '').lower()
    if t.startswith('completed'):
        return 'completed'
    if 'not solarized' in t:
        return 'not_solarized'
    if 'unfunded' in t:
        return 'unfunded'
    if 'hold' in t:
        return 'on_hold'
    return 'planned'


def donor_group(raw):
    t = (raw or '').strip()
    if not t:
        return None
    first = re.split(r'[\s/]+', t)[0]
    up = first.upper()
    if up.startswith('KFW'):
        return 'KfW'
    if up.startswith('NRC'):
        return 'NRC'
    return first


for hdr, r in rows(solar_wb['Solarized Schools']):
    c = cerd(r[0])
    if c is None:
        continue
    s = school(c)
    raw_status = text(r[4])
    donor = text(r[3])
    con = contractors.get(c, (None, None))
    shift = text(r[13])
    s['solar'] = OrderedDict(
        listedName=text(r[1]),
        status=solar_status(raw_status),
        statusRaw=raw_status,
        donor=donor,
        donorGroup=donor_group(donor),
        project=text(r[10]),
        costUsd=num(r[5]),
        kwp=num(r[6]),
        inverterKw=num(r[7]),
        batteryKwh=num(r[8]),
        enrollment2324=intval(r[9]),
        qaCostUsd=num(r[11]),
        ledCostUsd=num(r[12]),
        shift=None if shift in (None, '0') else shift,
        language=text(r[14]),
        contractor=con[0],
        consultant=con[1],
    )
    if not s.get('name'):
        s['name'] = text(r[1])
    if not s.get('region'):
        s['region'] = GOV.get((text(r[2]) or '').lower())

# ------------------------------------------------------------ energy loads
energy_wb = wb('Energy_Breakdown')
for hdr, r in rows(energy_wb['Sheet2']):
    c = cerd(r[0])
    if c is None:
        continue
    s = school(c)
    s['loads'] = OrderedDict(lightingKwh=num(r[2]) or 0.0, hvacKwh=num(r[3]) or 0.0, itKwh=num(r[4]) or 0.0, miscKwh=num(r[5]) or 0.0)
    if not s.get('name'):
        s['name'] = text(r[1])

CATEGORY = {'lighting': 'Lighting', 'hvac': 'HVAC', 'it': 'IT', 'miscellaneous': 'Miscellaneous'}
for hdr, r in rows(energy_wb['Sheet1']):
    c = cerd(r[0])
    if c is None:
        continue
    s = school(c)
    items = []
    for g in range(2, len(hdr) - 5, 6):
        if hdr[g] != 'Type of equipment':
            continue
        t = text(r[g])
        if not t or t.lower() in ('x', '0'):
            continue
        watts, count, hours, annual = num(r[g + 1]), num(r[g + 2]), num(r[g + 3]), num(r[g + 4])
        if not any((watts, count, hours, annual)):
            continue
        cat = CATEGORY.get((text(r[g + 5]) or '').lower(), text(r[g + 5]) or 'Other')
        items.append([t, cat, watts or 0, int(count or 0), hours or 0, annual or 0])
    if items:
        s['equipment'] = items
    if not s.get('name'):
        s['name'] = text(r[1])

# --------------------------------------------------------------- education
edu_wb = wb('EDU_Dashboard')
for hdr, r in rows(edu_wb['School List']):
    c = cerd(r[0])
    if c is None:
        continue
    s = school(c)
    s.setdefault('pmCerd', intval(r[1]))
    if not s.get('name'):
        s['name'] = text(r[2])

for hdr, r in rows(edu_wb['Student Attendance']):
    c = cerd(r[0])
    if c is None:
        continue
    s = school(c)
    terms = [intval(r[i]) for i in (11, 12, 13, 14)]
    s['education'] = OrderedDict(
        shift=text(r[1]),
        amSubmitted=yes(r[2]),
        amAttendance=num(r[3]),
        amAbsence10Rate=num(r[4]),
        pmSubmitted=yes(r[5]),
        pmAttendance=num(r[6]),
        pmAbsence10Rate=num(r[7]),
        amRisk=risk(r[8]),
        pmRisk=risk(r[9]),
        pmTeachers=intval(r[10]),
        pmTeacherAttendanceTerms=terms if any(t is not None for t in terms) else None,
        studentTeacherRatio=num(r[15]),
        visitedThirdParty=yes(r[16]),
        pmTeacherRisk=risk(r[17]),
        pmFemaleTeachers=intval(r[18]),
        pmMaleTeachers=intval(r[19]),
        teachingDays=intval(r[20]),
    )

for hdr, r in rows(edu_wb['Student Risk Level']):
    c = cerd(r[0])
    if c is None or c not in schools:
        continue
    monthly = OrderedDict()
    for i in range(1, len(hdr) - 2):
        v = risk(r[i])
        if v:
            monthly[hdr[i].replace('Risk Level ', '')] = v
    if monthly:
        schools[c].setdefault('education', OrderedDict())['monthlyStudentRisk'] = monthly

for hdr, r in rows(edu_wb['PM Teachers Risk Level']):
    c = cerd(r[0])
    if c is None or c not in schools:
        continue
    edu = schools[c].setdefault('education', OrderedDict())
    edu['visitedByBdo'] = yes(r[1])
    monthly = OrderedDict()
    for i in range(2, len(hdr) - 1):
        v = risk(r[i])
        if v:
            monthly[hdr[i].replace('Risk Level ', '')] = v
    if monthly:
        edu['monthlyTeacherRisk'] = monthly

# ------------------------------------------------------------------ output
for s in schools.values():
    s.setdefault('connected', False)
    s.setdefault('name', s.get('nameAr'))
out = OrderedDict(
    version=1,
    generatedAt='2026-09-11',
    sources=[
        'Overview_of_Public_Schools.xlsx (MEHE public school master list)',
        'Connectivity534Schools.xlsx (schools with internet connectivity)',
        'Public_Schools_Solar_Implementation.xlsx (UNICEF solarisation status, donors, contractors)',
        'Energy_Breakdown.xlsx (equipment inventory and annual load by category, kWh/year)',
        'EDU_Dashboard_Data.xlsx (attendance and risk indicators)',
    ],
    schools=[s for s in sorted(schools.values(), key=lambda s: s['cerd'])],
)
os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
with open(OUT, 'w', encoding='utf-8') as f:
    json.dump(out, f, ensure_ascii=False, separators=(',', ':'))

# Summary
vals = list(schools.values())
print(f'schools: {len(vals)}  in master: {sum(1 for s in vals if s["inMaster"])}  connected: {sum(1 for s in vals if s["connected"])}')
print('solar:', Counter(s['solar']['status'] for s in vals if 'solar' in s))
print('with loads:', sum(1 for s in vals if 'loads' in s), 'with equipment:', sum(1 for s in vals if 'equipment' in s), 'equipment rows:', sum(len(s.get('equipment', [])) for s in vals))
print('with education:', sum(1 for s in vals if 'education' in s))
print('region:', Counter(s.get('region') for s in vals))
print('no coordinates:', sum(1 for s in vals if s.get('lat') is None), ' no name:', sum(1 for s in vals if not s.get('name')))
print('size:', os.path.getsize(OUT) // 1024, 'KiB ->', OUT)
