#!/usr/bin/env python3
"""
Waybar weather widget
  · Zero external dependencies  (só stdlib)
  · Localização detectada automaticamente por IP na 1ª execução (cacheada)
  · Para forçar nova cidade: rm ~/.cache/waybar_weather_location
  · Unidade: variável WAYBAR_WEATHER_UNIT=C (padrão) ou F
"""

import json
import os
import urllib.parse
import urllib.request

# ── Configuração ──────────────────────────────────────────────────────────────
LOCATION_CACHE = os.path.expanduser("~/.cache/waybar_weather_location")
UNIT = os.environ.get("WAYBAR_WEATHER_UNIT", "C").upper()  # "C" ou "F"
TIMEOUT = 10


def _get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "waybar-weather/2.0"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.read()


def get_location() -> str:
    """Retorna cidade cacheada ou detecta via ipinfo.io."""
    if os.path.exists(LOCATION_CACHE):
        loc = open(LOCATION_CACHE).read().strip()
        if loc:
            return loc

    try:
        data = json.loads(_get("https://ipinfo.io/json"))
        city = data.get("city") or data.get("region") or ""
        if city:
            os.makedirs(os.path.dirname(LOCATION_CACHE), exist_ok=True)
            open(LOCATION_CACHE, "w").write(city)
            return city
    except Exception:
        pass

    return "auto"  # wttr.in resolve automaticamente por IP como fallback


def fetch_weather(location: str) -> dict:
    url = f"https://wttr.in/{urllib.parse.quote(location)}?format=j1"
    return json.loads(_get(url))


def main() -> None:
    location = get_location()

    try:
        data = fetch_weather(location)
    except Exception as exc:
        print(
            json.dumps({"text": "⚠️ N/A", "tooltip": str(exc), "class": "weather-error"})
        )
        return

    cur = data["current_condition"][0]
    today = data["weather"][0]
    code = int(cur["weatherCode"])
    icon = ""

    if UNIT == "F":
        temp, feels = cur["temp_F"], cur["FeelsLikeF"]
        hi, lo = today["maxtempF"], today["mintempF"]
        sym = "°F"
    else:
        temp, feels = cur["temp_C"], cur["FeelsLikeC"]
        hi, lo = today["maxtempC"], today["mintempC"]
        sym = "°C"

    desc = cur["weatherDesc"][0]["value"]
    humidity = cur["humidity"]
    wind_kmh = cur["windspeedKmph"]

    # Previsão dos próximos 2 dias
    forecast_lines = []
    days_pt = ["Amanhã", "Depois de amanhã"]
    for i, label in enumerate(days_pt):
        if i + 1 < len(data["weather"]):
            d = data["weather"][i + 1]
            d_hi = d["maxtempC"] if UNIT != "F" else d["maxtempF"]
            d_lo = d["mintempC"] if UNIT != "F" else d["mintempF"]
            d_desc = d["hourly"][4]["weatherDesc"][0]["value"]  # ≈ meio-dia
            forecast_lines.append(f"{label}: {d_desc} {d_lo}{sym}–{d_hi}{sym}")

    tooltip = (
        f"{icon} {desc}\n"
        f"━━━━━━━━━━━━━━━━━━━\n"
        f"Atual:      {temp}{sym}\n"
        f"Sensação:   {feels}{sym}\n"
        f"Min / Max:  {lo}{sym} / {hi}{sym}\n"
        f"Umidade:    {humidity}%\n"
        f"Vento:      {wind_kmh} km/h\n"
        f"📍 {location}\n"
    )
    if forecast_lines:
        tooltip += "━━━━━━━━━━━━━━━━━━━\n" + "\n".join(forecast_lines)

    print(
        json.dumps(
            {
                "text": f"{icon} {temp}{sym}",
                "tooltip": tooltip,
                "class": "weather",
            }
        )
    )


if __name__ == "__main__":
    main()
