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
    weapon = {"name": "Odd gun [STRANGE POWER]", "kind": "ranged", "range": '24"', "a": "1", "skill": "3+", "s": "4", "ap": "0", "d": "1"}
    _, issues = m.map_unit(fake(weapons=[weapon]))
    assert any("STRANGE POWER" in i[1] and "not applied" in i[1] for i in issues)


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


def test_default_loadout_without_melee_gets_one_added_and_flagged():
    unit, issues = m.map_unit(fake(composition_raw=["■ 1 Test", "This model is equipped with: zap rifle."]))
    names = [w["name"] for w in unit["weapons"]]
    assert "Fists" in names
    assert any(i[0] == "warn" and "no melee" in i[1] for i in issues)


def test_same_name_ranged_and_melee_profiles_are_both_kept():
    rec = fake(composition_raw=["■ 1 Test", "This model is equipped with: zap staff."])
    rec["weapons"] = [
        {"name": "Zap staff [BLAST]", "kind": "ranged", "range": '24"', "a": "1", "skill": "3+", "s": "5", "ap": "-1", "d": "2"},
        {"name": "Zap staff", "kind": "melee", "range": "Melee", "a": "3", "skill": "3+", "s": "5", "ap": "-1", "d": "2"}]
    unit, issues = m.map_unit(rec)
    assert sorted(w["range"] for w in unit["weapons"]) == [0, 24]
    assert not any("no melee" in i[1] for i in issues)


def test_squashed_ability_names_are_restored():
    assert m.clean_tag("DEVASTATINGWOUNDS") == "DEVASTATING WOUNDS"
    assert m.clean_tag("SUSTAINEDHITS1") == "SUSTAINED HITS 1"
    assert m.clean_tag("RAPIDFIRE2") == "RAPID FIRE 2"
    assert m.clean_tag("ANTI-VEHICLE4+") == "ANTI-VEHICLE 4+"
    assert m.clean_tag("LETHALHITS:VEHICLE") == "LETHAL HITS: VEHICLE"


def test_abilities_that_are_already_clean_are_unchanged():
    assert m.clean_tag("HEAVY") == "HEAVY"
    assert m.clean_tag("ANTI-EPIC HERO 2+") == "ANTI-EPIC HERO 2+"


def test_squashed_tag_is_not_reported_as_a_typo():
    _, issues = m.map_unit(fake(weapons=[{"name": "Gun [RAPIDFIRE1]", "kind": "ranged", "range": '24"', "a": "1", "skill": "3+", "s": "4", "ap": "0", "d": "1"}]))
    assert not any("typo" in text for _, text in issues)


def test_core_abilities_become_engine_data():
    unit, _ = m.map_unit(fake(ability_text=["CORE: Deadly Demise D3, Feel No Pain 5+, Stealth", "CORE: Lone Operative, Fights First"]))
    assert unit["fnp"] == 5
    assert unit["deadly_demise"] == "D3"
    assert set(unit["abilities"]) == {"STEALTH", "LONE OPERATIVE", "FIGHTS FIRST"}


def test_core_ability_the_engine_lacks_is_logged_with_its_stand_in():
    _, issues = m.map_unit(fake(ability_text=["CORE: Deep Strike"]))
    assert any("Deep Strike" in text and "deploys normally" in text for _, text in issues)


def test_faction_ability_is_logged_as_not_applied():
    _, issues = m.map_unit(fake(ability_text=["FACTION: Test Protocol"]))
    assert any("Test Protocol" in text and "not applied" in text for _, text in issues)


def test_dice_valued_ability_becomes_its_fixed_average():
    weapon = {"name": "Gun [SUSTAINED HITS D3, RAPID FIRE D6]", "kind": "ranged", "range": '24"', "a": "1", "skill": "3+", "s": "4", "ap": "0", "d": "1"}
    unit, issues = m.map_unit(fake(weapons=[weapon], composition_raw=["■ 1 Test", "This model is equipped with: gun."]))
    assert unit["weapons"][0]["abilities"] == ["SUSTAINED HITS 2", "RAPID FIRE 4"]
    assert any("SUSTAINED HITS D3" in text and "fixed" in text for _, text in issues)
