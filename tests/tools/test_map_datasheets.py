"""Tests for the datasheet mapper, using invented units only (no real datasheet text)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools" / "datasheets"))
import map_datasheets as m  # noqa: E402


def fake(**over):
    rec = {
        "name": "TEST SQUAD", "source_file": "TEST SQUAD.pdf",
        "profiles": [{"m": '6"', "t": "4", "sv": "3+", "w": "2", "ld": "6+", "oc": "1"}],
        "weapons": [
            {"name": "Zap rifle [RAPID FIRE 1]", "kind": "ranged", "range": '24"', "a": "1", "skill": "3+", "s": "4", "ap": "-1", "d": "1"},
            {"name": "Zap blaster [TWIN-LINKED]", "kind": "ranged", "range": '12"', "a": "2", "skill": "3+", "s": "5", "ap": "0", "d": "1"},
            {"name": "Fists", "kind": "melee", "range": "Melee", "a": "2", "skill": "3+", "s": "4", "ap": "0", "d": "1"},
        ],
        "keywords": ["Infantry"], "faction_keywords": ["Testers"], "invuln_printed": None,
        "composition_raw": ["■ 5-10 Test Troopers", "Every model is equipped with: zap rifle; fists."],
        "page2_raw": [], "ability_text": [], "unparsed": [],
    }
    rec.update(over)
    return rec


def test_default_loadout_and_counts():
    unit, issues = m.map_unit(fake())
    assert unit["models_min"] == 5 and unit["models_max"] == 10
    assert [w["name"] for w in unit["weapons"]] == ["Zap rifle", "Fists"]
    assert unit["weapons"][0]["ap"] == 1 and unit["weapons"][0]["abilities"] == ["RAPID FIRE 1"]
    assert any("optional weapons" in i[1] and "Zap blaster" in i[1] for i in issues)


def test_unsupported_ability_is_reported():
    _, issues = m.map_unit(fake(composition_raw=["■ 1 Test", "This model is equipped with: zap blaster."]))
    assert any("TWIN-LINKED" in i[1] and "not applied" in i[1] for i in issues)


def test_typos_in_source_are_fixed_and_logged():
    rec = fake()
    rec["weapons"][0]["name"] = "Zap rifle [ANTI-VECHILE 4+]"
    unit, issues = m.map_unit(rec)
    assert unit["weapons"][0]["abilities"] == ["ANTI-VEHICLE 4+"]
    assert any(i[0] == "warn" and "typo" in i[1] for i in issues)


def test_quantity_kept():
    unit, _ = m.map_unit(fake(composition_raw=["■ 1 Test", "This model is equipped with: 2 zap blasters."]))
    assert unit["weapons"][0]["count"] == 2


def test_missing_stat_line_is_an_error():
    unit, issues = m.map_unit(fake(profiles=[]))
    assert unit is None and issues[0][0] == "error"
