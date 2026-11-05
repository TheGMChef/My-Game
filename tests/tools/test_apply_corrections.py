"""Tests for the correction layer, using invented units only."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools" / "datasheets"))
import apply_corrections as c  # noqa: E402


def army():
    gun = {"name": "Zap gun", "range": 24, "attacks": "2", "skill": 3, "strength": 4, "ap": 0, "damage": "1", "abilities": ["HEAVY"]}
    return {"units": [{"name": "TEST SQUAD", "move": 6, "keywords": ["INFANTRY", "FLY"], "abilities": [], "faction_abilities": [],
                       "weapons": [dict(gun)], "all_weapons": [dict(gun)]}]}


def test_stats_and_lists_change():
    a = army()
    log, problems = c.apply(a, {"units": {"TEST SQUAD": {"source": "pack 1", "set": {"move": 8}, "add_keywords": ["FRAME"],
                                                         "remove_keywords": ["FLY"], "add_abilities": ["STEALTH"], "add_faction_abilities": ["SYNAPSE"]}}})
    u = a["units"][0]
    assert u["move"] == 8 and u["keywords"] == ["INFANTRY", "FRAME"]
    assert u["abilities"] == ["STEALTH"] and u["faction_abilities"] == ["SYNAPSE"]
    assert len(log) == 1 and problems == [] and u["corrected_from"] == "pack 1"


def test_weapon_changes_reach_both_weapon_lists():
    a = army()
    c.apply(a, {"units": {"TEST SQUAD": {"weapons": {"Zap gun": {"set": {"ap": 2, "name": "Big gun"}, "add_abilities": ["BLAST"], "remove_abilities": ["HEAVY"]}}}}})
    for bucket in ("weapons", "all_weapons"):
        w = a["units"][0][bucket][0]
        assert w["ap"] == 2 and w["name"] == "Big gun" and w["abilities"] == ["BLAST"]


def test_removing_adding_and_replacing_weapons():
    a = army()
    knife = {"name": "Knife", "range": 0}
    c.apply(a, {"units": {"TEST SQUAD": {"remove_weapons": ["Zap gun"], "add_weapons": [knife]}}})
    assert [w["name"] for w in a["units"][0]["weapons"]] == ["Knife"]
    c.apply(a, {"units": {"TEST SQUAD": {"replace_weapons": [{"name": "Claw", "range": 0}]}}})
    assert [w["name"] for w in a["units"][0]["weapons"]] == ["Claw"]


def test_new_unit_is_added():
    a = army()
    log, _ = c.apply(a, {"new_units": [{"name": "NEW ONE", "source": "pack 2"}]})
    assert [u["name"] for u in a["units"]] == ["TEST SQUAD", "NEW ONE"] and "pack 2" in log[0]


def test_a_name_that_matches_nothing_is_reported():
    a = army()
    _, problems = c.apply(a, {"units": {"NOBODY": {}, "TEST SQUAD": {"weapons": {"Nothing": {}}}}, "new_units": [{"name": "TEST SQUAD"}]})
    assert len(problems) == 3


def test_uncertain_change_is_flagged_in_the_log():
    a = army()
    log, _ = c.apply(a, {"units": {"TEST SQUAD": {"source": "pack", "uncertain": True}}})
    assert "uncertain" in log[0]
