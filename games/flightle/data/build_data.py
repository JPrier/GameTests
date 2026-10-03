#!/usr/bin/env python3
"""Builds data/flightle.json for Flightle.

Inputs (downloaded once, not committed):
  airports.json  https://raw.githubusercontent.com/mwgg/Airports/master/airports.json
  land.json      https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_land.geojson

Usage: python3 build_data.py <airports.json> <land.json>

Routes are real, regularly flown routes with a typical operator, aircraft type and
an approximate local departure time. The path is the great-circle track; the
altitude profile is modelled from distance and aircraft type.
"""
import json
import math
import sys

# FROM-TO | airline | aircraft | typical local departure
ROUTES = """
JFK-LAX|Delta Air Lines|Airbus A321neo|07:00
SFO-EWR|United Airlines|Boeing 777-200|07:30
ATL-MCO|Delta Air Lines|Boeing 737-900ER|09:15
ORD-DEN|United Airlines|Boeing 737 MAX 9|10:05
DFW-MIA|American Airlines|Boeing 737-800|13:20
SEA-ANC|Alaska Airlines|Boeing 737-900ER|16:45
LAS-SFO|Southwest Airlines|Boeing 737-800|18:30
BOS-DCA|American Airlines|Embraer E175|06:00
HNL-LAX|Hawaiian Airlines|Airbus A330-200|13:40
DEN-PHX|Southwest Airlines|Boeing 737 MAX 8|12:10
MSP-DTW|Delta Air Lines|Airbus A220-300|15:30
IAH-ORD|United Airlines|Boeing 737-900|07:25
CLT-LGA|American Airlines|Airbus A321|17:05
SLC-BOI|Delta Air Lines|Embraer E175|11:50
FLL-ATL|Spirit Airlines|Airbus A320neo|20:15
PDX-SFO|Alaska Airlines|Embraer E175|08:40
AUS-JFK|JetBlue|Airbus A320|06:30
MDW-BWI|Southwest Airlines|Boeing 737-700|07:10
OGG-HNL|Hawaiian Airlines|Boeing 717|09:00
SAN-SEA|Alaska Airlines|Boeing 737-800|14:20
YYZ-YVR|Air Canada|Boeing 787-9|08:00
YUL-YYZ|Air Canada|Airbus A220-300|07:00
YYC-YVR|WestJet|Boeing 737-800|10:30
YVR-YYJ|Air Canada|De Havilland Dash 8-400|12:00
JFK-LHR|British Airways|Boeing 777-300ER|18:30
FRA-ORD|Lufthansa|Boeing 747-8|10:00
CDG-JFK|Air France|Boeing 777-300ER|10:30
AMS-ATL|Delta Air Lines|Airbus A330-900neo|10:20
DUB-BOS|Aer Lingus|Airbus A321LR|15:30
KEF-SEA|Icelandair|Boeing 757-200|17:00
MAD-MIA|Iberia|Airbus A350-900|12:05
LHR-YYZ|Air Canada|Boeing 787-9|13:00
LIS-EWR|TAP Air Portugal|Airbus A330-900neo|10:30
ZRH-JFK|Swiss|Boeing 777-300ER|13:00
FCO-JFK|ITA Airways|Airbus A350-900|10:00
IST-IAD|Turkish Airlines|Boeing 777-300ER|14:40
MUC-SFO|Lufthansa|Airbus A350-900|16:00
MAN-JFK|Virgin Atlantic|Airbus A330-300|10:40
LHR-LAX|Virgin Atlantic|Airbus A350-1000|12:40
BCN-JFK|Level|Airbus A330-200|17:05
LHR-EDI|British Airways|Airbus A320|07:20
LGW-BCN|easyJet|Airbus A320neo|06:15
STN-DUB|Ryanair|Boeing 737-800|08:00
CDG-NCE|Air France|Airbus A320|09:00
FRA-BER|Lufthansa|Airbus A321|07:00
AMS-LHR|KLM|Boeing 737-800|07:35
MAD-BCN|Iberia|Airbus A321|08:00
FCO-LIN|ITA Airways|Airbus A320|07:00
OSL-TRD|Norwegian|Boeing 737-800|08:30
ARN-HEL|Finnair|Airbus A320|09:20
CPH-OSL|SAS|Airbus A320neo|10:00
VIE-ZRH|Austrian Airlines|Airbus A320|07:05
ATH-JTR|Aegean Airlines|Airbus A320|11:30
LIS-FNC|TAP Air Portugal|Airbus A320neo|09:00
WAW-KRK|LOT Polish Airlines|Embraer E195|07:45
BUD-LTN|Wizz Air|Airbus A321neo|06:00
IST-ESB|Turkish Airlines|Airbus A321|08:00
DUB-LHR|Aer Lingus|Airbus A320|07:00
GVA-LHR|Swiss|Airbus A220-300|07:40
PMI-MAN|Jet2|Boeing 737-800|15:10
TFS-LGW|TUI Airways|Boeing 737 MAX 8|12:25
PRG-CDG|Air France|Airbus A320|13:00
OPO-STN|Ryanair|Boeing 737-800|12:10
DXB-LHR|Emirates|Airbus A380|07:45
DOH-SYD|Qatar Airways|Airbus A350-1000|20:30
DXB-JFK|Emirates|Airbus A380|08:30
AUH-LHR|Etihad Airways|Airbus A380|02:40
DOH-LHR|Qatar Airways|Boeing 777-300ER|07:30
TLV-JFK|El Al|Boeing 787-9|00:50
RUH-JED|Saudia|Airbus A320neo|09:00
DXB-BOM|Emirates|Boeing 777-300ER|03:30
IST-DXB|Turkish Airlines|Airbus A330-300|19:00
HND-CTS|Japan Airlines|Airbus A350-900|08:00
HND-ITM|ANA|Boeing 787-8|07:00
HND-FUK|ANA|Boeing 777-200|10:00
GMP-CJU|Korean Air|Boeing 737-900|08:30
ICN-LAX|Korean Air|Boeing 777-300ER|14:30
PEK-SHA|Air China|Airbus A330-300|09:00
CAN-PEK|China Southern|Airbus A330-300|08:00
HKG-TPE|Cathay Pacific|Airbus A330-300|10:00
SIN-KUL|Singapore Airlines|Boeing 737 MAX 8|07:30
SIN-JFK|Singapore Airlines|Airbus A350-900ULR|23:35
SIN-LHR|Singapore Airlines|Airbus A380|23:05
BKK-HKT|Thai AirAsia|Airbus A320|07:00
DEL-BOM|IndiGo|Airbus A320neo|06:00
BLR-DEL|Air India|Airbus A320neo|08:30
HKG-LHR|Cathay Pacific|Airbus A350-1000|23:30
NRT-SFO|United Airlines|Boeing 787-9|17:00
MNL-CEB|Philippine Airlines|Airbus A321|07:00
CGK-DPS|Garuda Indonesia|Boeing 737-800|08:00
SGN-HAN|Vietnam Airlines|Airbus A321|06:00
TPE-LAX|EVA Air|Boeing 777-300ER|23:40
HND-HNL|Hawaiian Airlines|Airbus A330-200|22:55
PVG-PEK|China Eastern|Airbus A350-900|08:00
CMB-MLE|SriLankan Airlines|Airbus A320|08:30
SYD-MEL|Qantas|Boeing 737-800|06:00
SYD-LAX|Qantas|Airbus A380|11:15
PER-LHR|Qantas|Boeing 787-9|18:45
AKL-SYD|Air New Zealand|Airbus A321neo|07:00
AKL-WLG|Air New Zealand|Airbus A320|07:00
BNE-SYD|Virgin Australia|Boeing 737-800|08:00
MEL-ADL|Jetstar|Airbus A320|09:30
AKL-SFO|Air New Zealand|Boeing 787-9|21:00
SYD-NAN|Fiji Airways|Airbus A330-200|09:45
JNB-CPT|FlySafair|Boeing 737-800|06:00
ADD-NBO|Ethiopian Airlines|Boeing 787-8|09:00
CAI-JED|EgyptAir|Boeing 737-800|05:00
CMN-CDG|Royal Air Maroc|Boeing 737-800|07:00
LOS-LHR|British Airways|Boeing 787-9|23:15
JNB-ATL|Delta Air Lines|Airbus A350-900|20:10
NBO-JFK|Kenya Airways|Boeing 787-8|23:25
ADD-IAD|Ethiopian Airlines|Boeing 787-9|10:20
RAK-LGW|easyJet|Airbus A320|11:00
DSS-CDG|Air France|Airbus A350-900|23:45
GRU-GIG|LATAM|Airbus A320|07:00
MEX-CUN|Aeromexico|Boeing 737 MAX 8|08:00
BOG-MDE|Avianca|Airbus A320neo|06:00
SCL-LIM|LATAM|Airbus A320neo|08:00
EZE-SCL|Aerolineas Argentinas|Boeing 737-800|09:00
GRU-JFK|LATAM|Boeing 777-300ER|22:30
MEX-MAD|Aeromexico|Boeing 787-9|21:00
LIM-CUZ|LATAM|Airbus A320|05:00
PTY-MIA|Copa Airlines|Boeing 737 MAX 9|07:00
GRU-LIS|TAP Air Portugal|Airbus A330-900neo|15:40
CUN-JFK|JetBlue|Airbus A320|13:00
EZE-MAD|Iberia|Airbus A350-900|13:45
SCL-PUQ|Sky Airline|Airbus A320neo|07:00
MEX-TIJ|Volaris|Airbus A320neo|06:00
SJU-JFK|JetBlue|Airbus A321|06:00
HAV-MIA|American Airlines|Boeing 737-800|08:00
DFW-SYD|Qantas|Boeing 787-9|21:50
JFK-HKG|Cathay Pacific|Airbus A350-1000|01:25
LAX-SYD|Delta Air Lines|Airbus A350-900|22:30
YVR-NRT|Air Canada|Boeing 787-9|13:00
SEA-HND|Delta Air Lines|Airbus A330-900neo|12:30
ANC-FAI|Alaska Airlines|Boeing 737-900|07:00
GUM-HNL|United Airlines|Boeing 777-200ER|23:00
KEF-JFK|Icelandair|Boeing 757-200|16:40
FAO-LGW|British Airways|Airbus A320|13:00
HEL-NRT|Finnair|Airbus A350-900|17:30
SFO-HNL|United Airlines|Boeing 757-200|08:00
ORD-LHR|United Airlines|Boeing 787-10|17:45
CPT-LHR|British Airways|Airbus A350-1000|18:45
"""

# Extra well-known airports that can be guessed (decoys), beyond the route endpoints.
EXTRA = """
LGA EWR PHL IAD BWI PIT CLE CMH IND CVG STL MCI MSY BNA MEM RDU TPA RSW PBI JAX SAT HOU DAL OKC TUL
ABQ TUS ONT SNA BUR OAK SJC SMF RNO GEG MKE DSM OMA SDF BDL PVD BUF ALB ORF CHS SAV PWM BTV MSN
YOW YEG YWG YHZ YQB YXE YQR
CUN GDL MTY SJD PVR TLC BJX
SJO LIR SAL GUA TGU MGA BZE SDQ PUJ MBJ KIN NAS BGI POS AUA CUR
BOG CLO CTG UIO GYE LPB VVI ASU MVD BSB SSA REC FOR POA CWB CNF MAO BEL COR MDZ BRC USH AEP
LHR LCY BHX BRS GLA ABZ BFS NCL LPL ORK SNN
CDG ORY LYS MRS TLS BOD NTE BSL
FRA MUC DUS HAM CGN STR HAJ NUE LEJ
AMS EIN RTM BRU CRL LUX
MAD BCN AGP ALC VLC SVQ BIO IBZ LPA ACE
LIS OPO PDL
FCO MXP BGY VCE BLQ NAP PSA FLR CTA PMO BRI CAG OLB
ZRH GVA BSL VIE SZG INN
CPH BLL AAR OSL BGO SVG TOS ARN GOT MMX HEL OUL RVN KEF
WAW GDN WRO POZ PRG BRQ BUD BTS LJU ZAG SPU DBV BEG SKP TIA SOF VAR OTP CLJ KIV
ATH SKG HER RHO CFU JMK MLA LCA PFO
IST SAW AYT ADB DLM BJV TBS EVN GYD
TLV AMM BEY CAI HRG SSH LXR
DXB DWC AUH SHJ DOH BAH KWI MCT RUH DMM MED
ALG TUN TIP CMN RAK FEZ TNG AGA
LOS ABV ACC DKR ABJ ADD NBO MBA DAR ZNZ EBB KGL JNB CPT DUR WDH LUN HRE MRU SEZ TNR
KHI LHE ISB DEL BOM BLR MAA CCU HYD COK GOI AMD TRV DAC KTM CMB MLE
BKK DMK HKT CNX USM KUL PEN BKI SIN CGK DPS SUB MNL CEB SGN HAN DAD PNH REP RGN VTE
HKG MFM TPE KHH PEK PKX PVG SHA CAN SZX CTU TFU CKG XIY KMG HGH NKG XMN WUH CSX URC HRB
ICN GMP PUS CJU NRT HND KIX ITM NGO CTS FUK OKA SDJ HIJ KOJ
ULN ALA NQZ TAS
SYD MEL BNE PER ADL CBR OOL CNS DRW HBA AKL WLG CHC ZQN NAN PPT NOU APW GUM
HNL OGG KOA LIH ANC FAI JNU
""".split()

TURBOPROP = ("ATR", "Dash 8")
REGIONAL = ("Embraer E17", "Embraer E19", "CRJ")


def haversine(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a["lat"], a["lon"], b["lat"], b["lon"]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371.0 * math.asin(math.sqrt(h))


def cruise_ft(km, aircraft):
    """Typical initial / final cruise altitude in feet for the profile clue."""
    if any(t in aircraft for t in TURBOPROP):
        top = 25000
    elif any(t in aircraft for t in REGIONAL):
        top = 36000
    else:
        top = 37000
    base = 10000 + 27000 * (1 - math.exp(-km / 350))
    if km > 4500 and top > 25000:
        # long haul: start lower while heavy, step-climb as fuel burns off
        heavy = "A380" in aircraft or "747" in aircraft or "777" in aircraft
        final = 41000 if ("787" in aircraft or "A350" in aircraft) else 39000
        return (31000 if heavy else 33000), (37000 if heavy and km < 8000 else final)
    v = int(round(min(base, top) / 1000)) * 1000
    return v, v


def minutes(km, aircraft):
    speed = 500 if any(t in aircraft for t in TURBOPROP) else 820
    return int(round((km / speed * 60 + 22) / 5)) * 5


def short_name(a):
    n = a["name"]
    for s in (" International Airport", " Airport", " International", " Intl"):
        n = n.replace(s, "")
    return n.strip()


def main():
    airports = json.load(open(sys.argv[1]))
    by_iata = {v["iata"]: v for v in airports.values() if v.get("iata")}

    routes = []
    used = set()
    for line in ROUTES.strip().splitlines():
        pair, airline, aircraft, dep = line.split("|")
        f, t = pair.split("-")
        assert f in by_iata and t in by_iata, line
        km = haversine(by_iata[f], by_iata[t])
        c0, c1 = cruise_ft(km, aircraft)
        routes.append({"f": f, "t": t, "al": airline, "ac": aircraft, "dep": dep,
                       "km": int(round(km)), "min": minutes(km, aircraft), "c0": c0, "c1": c1})
        used.update((f, t))
    assert len({(r["f"], r["t"]) for r in routes}) == len(routes), "duplicate route"

    pool = sorted(used | {c for c in EXTRA if c in by_iata})
    missing = [c for c in EXTRA if c not in by_iata]
    if missing:
        print("skipped unknown extra codes:", missing, file=sys.stderr)
    aps = []
    for c in pool:
        a = by_iata[c]
        aps.append({"c": c, "n": short_name(a), "city": a["city"], "cc": a["country"],
                    "la": round(a["lat"], 4), "lo": round(a["lon"], 4)})

    land = json.load(open(sys.argv[2]))
    rings = []
    for feat in land["features"]:
        g = feat["geometry"]
        polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
        for poly in polys:
            ring = poly[0]
            flat = []
            for lo, la in ring:
                flat += [round(lo, 1), round(la, 1)]
            if len(flat) >= 8:
                rings.append(flat)

    out = {"airports": aps, "routes": routes, "land": rings}
    json.dump(out, open("flightle.json", "w"), separators=(",", ":"))
    print(f"{len(routes)} routes, {len(aps)} airports, {len(rings)} land rings")


if __name__ == "__main__":
    main()
