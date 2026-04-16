#!/usr/bin/env python3
"""Builds the runtime master-data bundle from the Mono-Spec JSON sources."""

import argparse
import json
import sys
import tempfile
from pathlib import Path

VALID_ENEMY_RACES = {
    "dragon",
    "monster",
    "zombie",
    "godfiend",
}

VALID_ACTION_KINDS = {
    "breath",
    "attack",
    "recoverySpell",
    "attackSpell",
}

VALID_SPELL_CATEGORIES = {
    "attack",
    "recovery",
}

VALID_SPELL_KINDS = {
    "damage",
    "buff",
    "heal",
    "cleanse",
    "barrier",
    "fullHeal",
}

VALID_TARGET_SIDES = {
    "ally",
    "enemy",
    "both",
}

VALID_EFFECT_TARGETS = {
    "physicalDamage",
    "magicDamage",
    "physicalDamageTaken",
    "magicDamageTaken",
}

VALID_SKILL_EFFECT_KINDS = {
    "battleStatModifier",
    "baseBattleStatMultiplier",
    "battleDerivedModifier",
    "partyModifier",
    "allBattleStatMultiplier",
    "rewardMultiplier",
    "equipmentCapacityModifier",
    "titleRollCountModifier",
    "normalDropJewelize",
    "magicAccess",
    "onHitAilmentGrant",
    "contactAilmentGrant",
    "multiHitFalloffModifier",
    "hitRateFloorModifier",
    "breathAccess",
    "interruptGrant",
    "defenseRule",
    "recoveryRule",
    "actionRule",
    "reviveRule",
    "combatRule",
    "rewardRule",
    "specialRule",
}

VALID_BATTLE_STAT_OPERATIONS = {
    "flatAdd",
    "pctAdd",
}

VALID_BATTLE_DERIVED_OPERATIONS = {
    "mul",
    "pctAdd",
}

VALID_REWARD_MULTIPLIER_OPERATIONS = {
    "mul",
    "pctAdd",
}

VALID_SKILL_ACCESS_OPERATIONS = {
    "grant",
    "revoke",
}

VALID_SKILL_CONDITIONS = {
    "unarmed",
}

VALID_BATTLE_STAT_TARGETS = {
    "maxHP",
    "physicalAttack",
    "physicalDefense",
    "magic",
    "magicDefense",
    "healing",
    "accuracy",
    "evasion",
    "attackCount",
    "criticalRate",
    "breathPower",
}

VALID_BATTLE_DERIVED_STAT_TARGETS = {
    "physicalDamageMultiplier",
    "magicDamageMultiplier",
    "spellDamageMultiplier",
    "criticalDamageMultiplier",
    "meleeDamageMultiplier",
    "rangedDamageMultiplier",
    "actionSpeedMultiplier",
    "physicalResistanceMultiplier",
    "magicResistanceMultiplier",
    "breathResistanceMultiplier",
}

VALID_REWARD_MULTIPLIER_TARGETS = {
    "goldGainMultiplier",
    "experienceGainMultiplier",
    "rareDropMultiplier",
    "titleDropMultiplier",
}

VALID_PARTY_MODIFIER_TARGETS = {
    "allyPhysicalDamageMultiplier",
    "allyMagicDamageMultiplier",
    "allyHealingMultiplier",
    "allyPhysicalDamageTakenMultiplier",
    "allyMagicDamageTakenMultiplier",
}

VALID_AILMENT_KEYS = {
    "sleep",
    "curse",
    "paralysis",
    "petrify",
}

VALID_INTERRUPT_KINDS = {
    "rescue",
    "counter",
    "extraAttack",
    "pursuit",
}

VALID_ITEM_RARITIES = {
    "normal",
    "uncommon",
    "rare",
    "mythic",
    "godfiend",
}

VALID_ITEM_CATEGORIES = {
    "sword",
    "katana",
    "bow",
    "wand",
    "rod",
    "armor",
    "shield",
    "robe",
    "gauntlet",
    "jewel",
    "misc",
}

VALID_ITEM_RANGE_CLASSES = {
    "none",
    "melee",
    "ranged",
}


def load_json(path: Path):
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as error:
        raise ValueError(f"Invalid JSON in {path}: {error}") from error


def require_keys(record: dict, keys: tuple[str, ...], context: str):
    missing = [key for key in keys if key not in record]
    if missing:
        joined = ", ".join(missing)
        raise ValueError(f"Missing required field(s) {joined} in {context}")


def validate_unique_keys(records: list[dict], source_name: str):
    seen: set[str] = set()
    for record in records:
        key = record["id"]
        if key in seen:
            raise ValueError(f"Duplicate key '{key}' in {source_name}")
        seen.add(key)


def keyed_indices(records: list[dict]) -> dict[str, int]:
    return {record["id"]: index for index, record in enumerate(records, start=1)}


def build_races(records: list[dict], skill_indices: dict[str, int]) -> list[dict]:
    races: list[dict] = []
    for index, record in enumerate(records, start=1):
        require_keys(record, ("id", "name", "levelCap", "baseHirePrice", "baseStats"), f"race[{index}]")
        base_stats = record["baseStats"]
        require_keys(
            base_stats,
            ("vitality", "strength", "mind", "intelligence", "agility", "luck"),
            f"race[{record['id']}].baseStats",
        )
        def build_skill_ids(raw_value: object, field_name: str) -> list[int]:
            if raw_value is None:
                return []
            if not isinstance(raw_value, list):
                raise ValueError(f"Expected race[{record['id']}].{field_name} to be an array")

            built_skill_ids: list[int] = []
            for skill_id in raw_value:
                if not isinstance(skill_id, str):
                    raise ValueError(f"Expected race[{record['id']}].{field_name} values to be strings")
                if skill_id not in skill_indices:
                    raise ValueError(f"Unknown skillId '{skill_id}' in race[{record['id']}]")
                built_skill_ids.append(skill_indices[skill_id])
            return built_skill_ids

        legacy_skill_ids = record.get("skillIds")
        passive_skill_ids = build_skill_ids(record.get("passiveSkillIds"), "passiveSkillIds")
        level_skill_ids = build_skill_ids(record.get("levelSkillIds"), "levelSkillIds")
        if not passive_skill_ids and not level_skill_ids and legacy_skill_ids is not None:
            passive_skill_ids = build_skill_ids(legacy_skill_ids, "skillIds")
        races.append(
            {
                "id": index,
                "key": record["id"],
                "name": record["name"],
                "levelCap": int(record["levelCap"]),
                "baseHirePrice": int(record["baseHirePrice"]),
                "baseStats": {
                    "vitality": int(base_stats["vitality"]),
                    "strength": int(base_stats["strength"]),
                    "mind": int(base_stats["mind"]),
                    "intelligence": int(base_stats["intelligence"]),
                    "agility": int(base_stats["agility"]),
                    "luck": int(base_stats["luck"]),
                },
                "passiveSkillIds": passive_skill_ids,
                "levelSkillIds": level_skill_ids,
            }
        )
    return races


def build_jobs(records: list[dict], skill_indices: dict[str, int]) -> list[dict]:
    coefficient_keys = (
        "maxHP",
        "physicalAttack",
        "physicalDefense",
        "magic",
        "magicDefense",
        "healing",
        "accuracy",
        "evasion",
        "attackCount",
        "criticalRate",
        "breathPower",
    )
    job_indices = keyed_indices(records)
    jobs: list[dict] = []
    for index, record in enumerate(records, start=1):
        require_keys(record, ("id", "name", "hirePriceMultiplier", "coefficients"), f"job[{index}]")
        coefficients = record["coefficients"]
        require_keys(coefficients, coefficient_keys, f"job[{record['id']}].coefficients")

        def build_skill_ids(raw_value: object, field_name: str) -> list[int]:
            if raw_value is None:
                return []
            if not isinstance(raw_value, list):
                raise ValueError(f"Expected job[{record['id']}].{field_name} to be an array")

            built_skill_ids: list[int] = []
            for skill_id in raw_value:
                if not isinstance(skill_id, str):
                    raise ValueError(f"Expected job[{record['id']}].{field_name} values to be strings")
                if skill_id not in skill_indices:
                    raise ValueError(f"Unknown skillId '{skill_id}' in job[{record['id']}]")
                built_skill_ids.append(skill_indices[skill_id])
            return built_skill_ids

        passive_skill_ids = build_skill_ids(record.get("passiveSkillIds"), "passiveSkillIds")
        level_skill_ids = build_skill_ids(record.get("levelSkillIds"), "levelSkillIds")
        raw_requirement = record.get("jobChangeRequirement")
        job_change_requirement = None
        if raw_requirement is not None:
            if not isinstance(raw_requirement, dict):
                raise ValueError(f"Expected job[{record['id']}].jobChangeRequirement to be an object")
            allowed_keys = {"requiredCurrentJobId", "requiredLevel"}
            unexpected_keys = sorted(set(raw_requirement) - allowed_keys)
            if unexpected_keys:
                unexpected_keys_text = ", ".join(unexpected_keys)
                raise ValueError(
                    f"Unexpected field(s) {unexpected_keys_text} in job[{record['id']}].jobChangeRequirement"
                )
            required_current_job_id = raw_requirement.get("requiredCurrentJobId", "")
            required_level = raw_requirement.get("requiredLevel", 0)
            if not isinstance(required_current_job_id, str):
                raise ValueError(
                    f"Expected job[{record['id']}].jobChangeRequirement.requiredCurrentJobId to be a string"
                )
            if required_current_job_id and required_current_job_id not in job_indices:
                raise ValueError(
                    f"Unknown requiredCurrentJobId '{required_current_job_id}' in job[{record['id']}]"
                )
            job_change_requirement = {
                "requiredCurrentJobId": job_indices.get(required_current_job_id, 0),
                "requiredLevel": int(required_level),
            }
        jobs.append(
            {
                "id": index,
                "key": record["id"],
                "name": record["name"],
                "hirePriceMultiplier": float(record["hirePriceMultiplier"]),
                "coefficients": {key: float(coefficients[key]) for key in coefficient_keys},
                "passiveSkillIds": passive_skill_ids,
                "levelSkillIds": level_skill_ids,
                "jobChangeRequirement": job_change_requirement,
            }
        )
    return jobs


def build_aptitudes(records: list[dict], skill_indices: dict[str, int]) -> list[dict]:
    aptitudes: list[dict] = []
    for index, record in enumerate(records, start=1):
        require_keys(record, ("id", "name"), f"aptitude[{index}]")

        def build_skill_ids(raw_value: object, field_name: str) -> list[int]:
            if raw_value is None:
                return []
            if not isinstance(raw_value, list):
                raise ValueError(f"Expected aptitude[{record['id']}].{field_name} to be an array")

            built_skill_ids: list[int] = []
            for skill_id in raw_value:
                if not isinstance(skill_id, str):
                    raise ValueError(f"Expected aptitude[{record['id']}].{field_name} values to be strings")
                if skill_id not in skill_indices:
                    raise ValueError(f"Unknown skillId '{skill_id}' in aptitude[{record['id']}]")
                built_skill_ids.append(skill_indices[skill_id])
            return built_skill_ids

        passive_skill_ids = build_skill_ids(record.get("passiveSkillIds"), "passiveSkillIds")
        aptitudes.append(
            {
                "id": index,
                "name": record["name"],
                "passiveSkillIds": passive_skill_ids,
            }
        )
    return aptitudes


def build_titles(records: list[dict]) -> list[dict]:
    titles: list[dict] = []
    for index, record in enumerate(records, start=1):
        require_keys(
            record,
            ("id", "name", "positiveMultiplier", "negativeMultiplier", "dropWeight"),
            f"title[{index}]",
        )
        titles.append(
            {
                "id": index,
                "key": record["id"],
                "name": record["name"],
                "positiveMultiplier": float(record["positiveMultiplier"]),
                "negativeMultiplier": float(record["negativeMultiplier"]),
                "dropWeight": int(record["dropWeight"]),
            }
        )
    return titles


def build_items(records: list[dict], skill_indices: dict[str, int]) -> list[dict]:
    base_stat_keys = ("vitality", "strength", "mind", "intelligence", "agility", "luck")
    battle_stat_keys = (
        "maxHP",
        "physicalAttack",
        "physicalDefense",
        "magic",
        "magicDefense",
        "healing",
        "accuracy",
        "evasion",
        "attackCount",
        "criticalRate",
        "breathPower",
    )

    def build_sparse_int_map(raw_values: dict, valid_keys: tuple[str, ...], context: str) -> dict[str, int]:
        if not isinstance(raw_values, dict):
            raise ValueError(f"Expected {context} to be an object")

        unexpected_keys = sorted(set(raw_values) - set(valid_keys))
        if unexpected_keys:
            unexpected_keys_text = ", ".join(unexpected_keys)
            raise ValueError(f"Unexpected field(s) {unexpected_keys_text} in {context}")

        return {key: int(raw_values[key]) for key in valid_keys if key in raw_values}

    items: list[dict] = []
    for index, record in enumerate(records, start=1):
        require_keys(
            record,
            (
                "id",
                "name",
                "category",
                "rarity",
                "basePrice",
                "nativeBaseStats",
                "nativeBattleStats",
                "skillIds",
                "rangeClass",
                "normalDropTier",
            ),
            f"item[{index}]",
        )

        category = record["category"]
        if category not in VALID_ITEM_CATEGORIES:
            raise ValueError(f"Unsupported category '{category}' in item[{record['id']}]")

        rarity = record["rarity"]
        if rarity not in VALID_ITEM_RARITIES:
            raise ValueError(f"Unsupported rarity '{rarity}' in item[{record['id']}]")

        range_class = record["rangeClass"]
        if range_class not in VALID_ITEM_RANGE_CLASSES:
            raise ValueError(f"Unsupported rangeClass '{range_class}' in item[{record['id']}]")

        normal_drop_tier = int(record["normalDropTier"])
        if normal_drop_tier < 0 or normal_drop_tier > 8:
            raise ValueError(f"Expected normalDropTier to be within 0...8 in item[{record['id']}]")
        if rarity == "normal" and category != "misc" and normal_drop_tier == 0:
            raise ValueError(
                "Expected normalDropTier to be within 1...8 "
                f"for normal item[{record['id']}]"
            )

        native_base_stats = build_sparse_int_map(
            record["nativeBaseStats"],
            base_stat_keys,
            f"item[{record['id']}].nativeBaseStats",
        )

        native_battle_stats = build_sparse_int_map(
            record["nativeBattleStats"],
            battle_stat_keys,
            f"item[{record['id']}].nativeBattleStats",
        )

        skill_ids = record["skillIds"]
        if not isinstance(skill_ids, list):
            raise ValueError(f"Expected item[{record['id']}].skillIds to be an array")
        for skill_id in skill_ids:
            if not isinstance(skill_id, str):
                raise ValueError(f"Expected item[{record['id']}].skillIds values to be strings")
            if skill_id not in skill_indices:
                raise ValueError(f"Unknown skillId '{skill_id}' in item[{record['id']}]")

        items.append(
            {
                "id": index,
                "name": record["name"],
                "category": category,
                "rarity": rarity,
                "basePrice": int(record["basePrice"]),
                "nativeBaseStats": {
                    key: native_base_stats.get(key, 0)
                    for key in base_stat_keys
                },
                "nativeBattleStats": {
                    key: native_battle_stats.get(key, 0)
                    for key in battle_stat_keys
                },
                "skillIds": [skill_indices[skill_id] for skill_id in skill_ids],
                "rangeClass": range_class,
                "normalDropTier": normal_drop_tier,
            }
        )
    return items


def build_super_rares(records: list[dict], skill_indices: dict[str, int]) -> list[dict]:
    super_rares: list[dict] = []
    for index, record in enumerate(records, start=1):
        require_keys(record, ("id", "name", "skillIds"), f"superRare[{index}]")
        skill_ids = record["skillIds"]
        if not isinstance(skill_ids, list):
            raise ValueError(f"Expected superRare[{record['id']}].skillIds to be an array")
        for skill_id in skill_ids:
            if not isinstance(skill_id, str):
                raise ValueError(f"Expected superRare[{record['id']}].skillIds values to be strings")
            if skill_id not in skill_indices:
                raise ValueError(f"Unknown skillId '{skill_id}' in superRare[{record['id']}]")
        super_rares.append(
            {
                "id": index,
                "name": record["name"],
                "skillIds": [skill_indices[skill_id] for skill_id in skill_ids],
            }
        )
    return super_rares


def build_spells(records: list[dict]) -> list[dict]:
    spells: list[dict] = []
    for index, record in enumerate(records, start=1):
        require_keys(
            record,
            ("id", "name", "category", "kind", "targetSide", "targetCount"),
            f"spell[{index}]",
        )
        category = record["category"]
        if category not in VALID_SPELL_CATEGORIES:
            raise ValueError(f"Unsupported category '{category}' in spell[{record['id']}]")

        kind = record["kind"]
        if kind not in VALID_SPELL_KINDS:
            raise ValueError(f"Unsupported kind '{kind}' in spell[{record['id']}]")

        target_side = record["targetSide"]
        if target_side not in VALID_TARGET_SIDES:
            raise ValueError(f"Unsupported targetSide '{target_side}' in spell[{record['id']}]")

        effect_target = record.get("effectTarget")
        if effect_target is not None and effect_target not in VALID_EFFECT_TARGETS:
            raise ValueError(f"Unsupported effectTarget '{effect_target}' in spell[{record['id']}]")

        status_id = record.get("statusId")
        if status_id is not None and int(status_id) <= 0:
            raise ValueError(f"Unsupported statusId '{status_id}' in spell[{record['id']}]")

        status_chance = record.get("statusChance")
        if status_chance is not None:
            status_chance = float(status_chance)
            if not 0.0 <= status_chance <= 1.0:
                raise ValueError(f"Unsupported statusChance '{status_chance}' in spell[{record['id']}]")

        spells.append(
            {
                "id": index,
                "name": record["name"],
                "category": category,
                "kind": kind,
                "targetSide": target_side,
                "targetCount": int(record["targetCount"]),
                "multiplier": float(record["multiplier"]) if "multiplier" in record else None,
                "effectTarget": effect_target,
                "statusId": int(status_id) if status_id is not None else None,
                "statusChance": status_chance,
            }
        )
    return spells


def build_skills(records: list[dict], spell_indices: dict[str, int]) -> list[dict]:
    skills: list[dict] = []
    for index, record in enumerate(records, start=1):
        require_keys(record, ("id", "name", "description", "effects"), f"skill[{index}]")
        description = record["description"]
        if not isinstance(description, str):
            raise ValueError(f"Expected skill[{record['id']}].description to be a string")

        effects = record["effects"]
        if not isinstance(effects, list) or not effects:
            raise ValueError(f"Expected skill[{record['id']}].effects to be a non-empty array")

        built_effects: list[dict] = []
        for effect_index, effect in enumerate(effects, start=1):
            require_keys(effect, ("kind",), f"skill[{record['id']}].effects[{effect_index}]")

            kind = effect["kind"]
            if kind not in VALID_SKILL_EFFECT_KINDS:
                raise ValueError(
                    f"Unsupported kind '{kind}' in skill[{record['id']}].effects[{effect_index}]"
                )

            condition = effect.get("condition")
            if condition is not None and condition not in VALID_SKILL_CONDITIONS:
                raise ValueError(
                    f"Unsupported condition '{condition}' in skill[{record['id']}].effects[{effect_index}]"
                )

            if kind in {
                "battleStatModifier",
                "baseBattleStatMultiplier",
                "battleDerivedModifier",
                "partyModifier",
                "rewardMultiplier",
            }:
                require_keys(
                    effect,
                    ("target", "operation", "value"),
                    f"skill[{record['id']}].effects[{effect_index}]",
                )
                target = effect["target"]
                if kind == "battleStatModifier":
                    valid_targets = VALID_BATTLE_STAT_TARGETS
                elif kind == "baseBattleStatMultiplier":
                    valid_targets = VALID_BATTLE_STAT_TARGETS
                elif kind == "battleDerivedModifier":
                    valid_targets = VALID_BATTLE_DERIVED_STAT_TARGETS
                elif kind == "partyModifier":
                    valid_targets = VALID_PARTY_MODIFIER_TARGETS
                else:
                    valid_targets = VALID_REWARD_MULTIPLIER_TARGETS
                if target not in valid_targets:
                    raise ValueError(
                        f"Unsupported target '{target}' in skill[{record['id']}].effects[{effect_index}]"
                    )

                operation = effect["operation"]
                if kind == "battleStatModifier":
                    valid_operations = VALID_BATTLE_STAT_OPERATIONS
                elif kind == "baseBattleStatMultiplier":
                    valid_operations = {"mul"}
                elif kind == "battleDerivedModifier":
                    valid_operations = VALID_BATTLE_DERIVED_OPERATIONS
                elif kind == "partyModifier":
                    valid_operations = VALID_BATTLE_DERIVED_OPERATIONS
                else:
                    valid_operations = VALID_REWARD_MULTIPLIER_OPERATIONS
                if operation not in valid_operations:
                    raise ValueError(
                        f"Unsupported operation '{operation}' in skill[{record['id']}].effects[{effect_index}]"
                    )

                effect_spell_ids = effect.get("spellIds", [])
                if not isinstance(effect_spell_ids, list):
                    raise ValueError(
                        f"Expected skill[{record['id']}].effects[{effect_index}].spellIds to be an array"
                    )
                built_spell_ids: list[int] = []
                for spell_id in effect_spell_ids:
                    if not isinstance(spell_id, str):
                        raise ValueError(
                            f"Expected skill[{record['id']}].effects[{effect_index}].spellIds values to be strings"
                        )
                    if spell_id not in spell_indices:
                        raise ValueError(
                            f"Unknown spellId '{spell_id}' in skill[{record['id']}].effects[{effect_index}]"
                        )
                    built_spell_ids.append(spell_indices[spell_id])

                built_effects.append(
                    {
                        "kind": kind,
                        "target": target,
                        "operation": operation,
                        "value": float(effect["value"]),
                        "spellIds": built_spell_ids,
                        "condition": condition,
                        "interruptKind": None,
                    }
                )
                continue

            if kind == "allBattleStatMultiplier":
                require_keys(effect, ("value",), f"skill[{record['id']}].effects[{effect_index}]")
                for unexpected_key in ("target", "operation", "spellIds", "interruptKind"):
                    if unexpected_key in effect:
                        raise ValueError(
                            f"Unexpected key '{unexpected_key}' in "
                            f"skill[{record['id']}].effects[{effect_index}]"
                        )
                built_effects.append(
                    {
                        "kind": kind,
                        "target": None,
                        "operation": None,
                        "value": float(effect["value"]),
                        "spellIds": [],
                        "condition": None,
                        "interruptKind": None,
                    }
                )
                continue

            if kind in {
                "equipmentCapacityModifier",
                "titleRollCountModifier",
                "normalDropJewelize",
                "multiHitFalloffModifier",
                "hitRateFloorModifier",
            }:
                require_keys(effect, ("value",), f"skill[{record['id']}].effects[{effect_index}]")
                for unexpected_key in ("target", "operation", "spellIds", "interruptKind"):
                    if unexpected_key in effect:
                        raise ValueError(
                            f"Unexpected key '{unexpected_key}' in "
                            f"skill[{record['id']}].effects[{effect_index}]"
                        )
                built_effects.append(
                    {
                        "kind": kind,
                        "target": None,
                        "operation": None,
                        "value": float(effect["value"]),
                        "spellIds": [],
                        "condition": None,
                        "interruptKind": None,
                    }
                )
                continue

            if kind == "onHitAilmentGrant":
                require_keys(effect, ("target", "value"), f"skill[{record['id']}].effects[{effect_index}]")
                target = effect["target"]
                if target not in VALID_AILMENT_KEYS:
                    raise ValueError(
                        f"Unsupported target '{target}' in skill[{record['id']}].effects[{effect_index}]"
                    )
                for unexpected_key in ("operation", "spellIds", "interruptKind"):
                    if unexpected_key in effect:
                        raise ValueError(
                            f"Unexpected key '{unexpected_key}' in "
                            f"skill[{record['id']}].effects[{effect_index}]"
                        )
                built_effects.append(
                    {
                        "kind": kind,
                        "target": target,
                        "operation": None,
                        "value": float(effect["value"]),
                        "spellIds": [],
                        "condition": None,
                        "interruptKind": None,
                    }
                )
                continue

            if kind == "contactAilmentGrant":
                require_keys(effect, ("target", "value"), f"skill[{record['id']}].effects[{effect_index}]")
                target = effect["target"]
                if target not in VALID_AILMENT_KEYS:
                    raise ValueError(
                        f"Unsupported target '{target}' in skill[{record['id']}].effects[{effect_index}]"
                    )
                for unexpected_key in ("operation", "spellIds", "interruptKind"):
                    if unexpected_key in effect:
                        raise ValueError(
                            f"Unexpected key '{unexpected_key}' in "
                            f"skill[{record['id']}].effects[{effect_index}]"
                        )
                built_effects.append(
                    {
                        "kind": kind,
                        "target": target,
                        "operation": None,
                        "value": float(effect["value"]),
                        "spellIds": [],
                        "condition": None,
                        "interruptKind": None,
                    }
                )
                continue

            if kind == "magicAccess":
                require_keys(effect, ("spellIds", "operation"), f"skill[{record['id']}].effects[{effect_index}]")
                operation = effect["operation"]
                if operation not in VALID_SKILL_ACCESS_OPERATIONS:
                    raise ValueError(
                        f"Unsupported operation '{operation}' in skill[{record['id']}].effects[{effect_index}]"
                    )
                spell_ids = effect["spellIds"]
                if not isinstance(spell_ids, list) or not spell_ids:
                    raise ValueError(
                        f"Expected skill[{record['id']}].effects[{effect_index}].spellIds to be a non-empty array"
                    )
                for spell_id in spell_ids:
                    if not isinstance(spell_id, str):
                        raise ValueError(
                            f"Expected skill[{record['id']}].effects[{effect_index}].spellIds values to be strings"
                        )
                    if spell_id not in spell_indices:
                        raise ValueError(
                            f"Unknown spellId '{spell_id}' in skill[{record['id']}].effects[{effect_index}]"
                        )

                built_effects.append(
                    {
                        "kind": kind,
                        "target": None,
                        "operation": operation,
                        "value": None,
                        "spellIds": [spell_indices[spell_id] for spell_id in spell_ids],
                        "condition": condition,
                        "interruptKind": None,
                    }
                )
                continue

            if kind == "breathAccess":
                built_effects.append(
                    {
                        "kind": kind,
                        "target": None,
                        "operation": None,
                        "value": None,
                        "spellIds": [],
                        "condition": None,
                        "interruptKind": None,
                    }
                )
                continue

            if kind == "specialRule":
                require_keys(effect, ("target", "value"), f"skill[{record['id']}].effects[{effect_index}]")
                target = effect["target"]
                if not isinstance(target, str) or not target:
                    raise ValueError(
                        f"Expected non-empty string target in skill[{record['id']}].effects[{effect_index}]"
                    )
                for unexpected_key in ("operation", "spellIds", "interruptKind"):
                    if unexpected_key in effect:
                        raise ValueError(
                            f"Unexpected key '{unexpected_key}' in "
                            f"skill[{record['id']}].effects[{effect_index}]"
                        )
                built_effects.append(
                    {
                        "kind": kind,
                        "target": target,
                        "operation": None,
                        "value": float(effect["value"]),
                        "spellIds": [],
                        "condition": condition,
                        "interruptKind": None,
                    }
                )
                continue

            if kind in {
                "defenseRule",
                "recoveryRule",
                "actionRule",
                "reviveRule",
                "combatRule",
                "rewardRule",
            }:
                require_keys(effect, ("target", "value"), f"skill[{record['id']}].effects[{effect_index}]")
                target = effect["target"]
                if not isinstance(target, str) or not target:
                    raise ValueError(
                        f"Expected non-empty string target in skill[{record['id']}].effects[{effect_index}]"
                    )
                for unexpected_key in ("operation", "spellIds", "interruptKind"):
                    if unexpected_key in effect:
                        raise ValueError(
                            f"Unexpected key '{unexpected_key}' in "
                            f"skill[{record['id']}].effects[{effect_index}]"
                        )
                built_effects.append(
                    {
                        "kind": kind,
                        "target": target,
                        "operation": None,
                        "value": float(effect["value"]),
                        "spellIds": [],
                        "condition": condition,
                        "interruptKind": None,
                    }
                )
                continue

            require_keys(effect, ("interruptKind",), f"skill[{record['id']}].effects[{effect_index}]")
            interrupt_kind = effect["interruptKind"]
            if interrupt_kind not in VALID_INTERRUPT_KINDS:
                raise ValueError(
                    f"Unsupported interruptKind '{interrupt_kind}' in skill[{record['id']}].effects[{effect_index}]"
                )

            built_effects.append(
                {
                    "kind": kind,
                    "target": None,
                    "operation": None,
                    "value": None,
                    "spellIds": [],
                    "condition": condition,
                    "interruptKind": interrupt_kind,
                }
            )

        skills.append(
            {
                "id": index,
                "name": record["name"],
                "description": description,
                "effects": built_effects,
            }
        )

    return skills


def build_recruit_names(record: dict) -> dict[str, list[str]]:
    recruit_names: dict[str, list[str]] = {}
    for pool_key in ("male", "female", "unisex"):
        if pool_key not in record:
            raise ValueError(f"Missing required field '{pool_key}' in names.json")
        pool_names = record[pool_key]
        if not isinstance(pool_names, list):
            raise ValueError(f"Expected names.{pool_key} to be an array")
        for entry in pool_names:
            if not isinstance(entry, str):
                raise ValueError(f"Expected all names.{pool_key} values to be strings")
        recruit_names[pool_key] = pool_names
    return recruit_names


def build_enemies(
    records: list[dict],
    job_indices: dict[str, int],
    skill_indices: dict[str, int],
    item_indices: dict[str, int],
) -> list[dict]:
    base_stat_keys = ("vitality", "strength", "mind", "intelligence", "agility", "luck")
    action_rate_keys = ("breath", "attack", "recoverySpell", "attackSpell")

    enemies: list[dict] = []
    for index, record in enumerate(records, start=1):
        require_keys(
            record,
            (
                "id",
                "name",
                "enemyRace",
                "jobKey",
                "baseStats",
                "goldBaseValue",
                "experienceBaseValue",
                "skillIds",
                "rareDropItemKeys",
                "actionRates",
                "actionPriority",
            ),
            f"enemy[{index}]",
        )

        enemy_race = record["enemyRace"]
        if enemy_race not in VALID_ENEMY_RACES:
            raise ValueError(f"Unsupported enemyRace '{enemy_race}' in enemy[{record['id']}]")

        job_key = record["jobKey"]
        if job_key not in job_indices:
            raise ValueError(f"Unknown jobKey '{job_key}' in enemy[{record['id']}]")

        base_stats = record["baseStats"]
        require_keys(base_stats, base_stat_keys, f"enemy[{record['id']}].baseStats")

        skill_ids = record["skillIds"]
        if not isinstance(skill_ids, list):
            raise ValueError(f"Expected enemy[{record['id']}].skillIds to be an array")
        for skill_id in skill_ids:
            if not isinstance(skill_id, str):
                raise ValueError(f"Expected enemy[{record['id']}].skillIds values to be strings")
            if skill_id not in skill_indices:
                raise ValueError(f"Unknown skillId '{skill_id}' in enemy[{record['id']}]")

        rare_drop_item_keys = record["rareDropItemKeys"]
        if not isinstance(rare_drop_item_keys, list):
            raise ValueError(f"Expected enemy[{record['id']}].rareDropItemKeys to be an array")
        for item_key in rare_drop_item_keys:
            if not isinstance(item_key, str):
                raise ValueError(f"Expected enemy[{record['id']}].rareDropItemKeys values to be strings")
            if item_key not in item_indices:
                raise ValueError(f"Unknown rareDropItemKey '{item_key}' in enemy[{record['id']}]")

        action_rates = record["actionRates"]
        require_keys(action_rates, action_rate_keys, f"enemy[{record['id']}].actionRates")

        action_priority = record["actionPriority"]
        if not isinstance(action_priority, list):
            raise ValueError(f"Expected enemy[{record['id']}].actionPriority to be an array")
        if len(action_priority) != 4:
            raise ValueError(f"Expected enemy[{record['id']}].actionPriority to contain exactly 4 entries")

        seen_action_kinds: set[str] = set()
        for action_kind in action_priority:
            if action_kind not in VALID_ACTION_KINDS:
                raise ValueError(f"Unsupported action kind '{action_kind}' in enemy[{record['id']}].actionPriority")
            if action_kind in seen_action_kinds:
                raise ValueError(f"Duplicate action kind '{action_kind}' in enemy[{record['id']}].actionPriority")
            seen_action_kinds.add(action_kind)

        enemies.append(
            {
                "id": index,
                "name": record["name"],
                "enemyRace": enemy_race,
                "jobId": job_indices[job_key],
                "baseStats": {key: int(base_stats[key]) for key in base_stat_keys},
                "goldBaseValue": int(record["goldBaseValue"]),
                "experienceBaseValue": int(record["experienceBaseValue"]),
                "skillIds": [skill_indices[skill_id] for skill_id in skill_ids],
                "rareDropItemIds": [item_indices[item_key] for item_key in rare_drop_item_keys],
                "actionRates": {key: int(action_rates[key]) for key in action_rate_keys},
                "actionPriority": action_priority,
            }
        )
    return enemies


def build_labyrinths(records: list[dict], enemy_indices: dict[str, int]) -> list[dict]:
    labyrinths: list[dict] = []
    next_floor_id = 1

    for labyrinth_index, record in enumerate(records, start=1):
        require_keys(
            record,
            ("id", "name", "enemyCountCap", "progressIntervalSeconds", "floors"),
            f"labyrinth[{labyrinth_index}]",
        )
        enemy_count_cap = int(record["enemyCountCap"])

        floors = record["floors"]
        if not isinstance(floors, list) or not floors:
            raise ValueError(f"Expected labyrinth[{record['id']}].floors to be a non-empty array")

        built_floors: list[dict] = []
        seen_floor_numbers: set[int] = set()
        for floor in floors:
            require_keys(
                floor,
                ("floorNumber", "battleCount", "encounters"),
                f"labyrinth[{record['id']}].floor",
            )

            floor_number = int(floor["floorNumber"])
            battle_count = int(floor["battleCount"])
            if floor_number in seen_floor_numbers:
                raise ValueError(f"Duplicate floorNumber '{floor_number}' in labyrinth[{record['id']}]")
            seen_floor_numbers.add(floor_number)

            encounters = floor["encounters"]
            if not isinstance(encounters, list):
                raise ValueError(
                    f"Expected labyrinth[{record['id']}].floors[{floor_number}].encounters to be an array"
                )

            fixed_battle = floor.get("fixedBattle")
            built_fixed_battle: list[dict] | None = None
            if fixed_battle is not None:
                if not isinstance(fixed_battle, list) or not fixed_battle:
                    raise ValueError(
                        f"Expected labyrinth[{record['id']}].floors[{floor_number}].fixedBattle to be a non-empty array"
                    )
                built_fixed_battle = []
                for enemy_entry in fixed_battle:
                    require_keys(
                        enemy_entry,
                        ("enemyKey", "level"),
                        f"labyrinth[{record['id']}].floors[{floor_number}].fixedBattle.enemy",
                    )
                    enemy_key = enemy_entry["enemyKey"]
                    if enemy_key not in enemy_indices:
                        raise ValueError(
                            f"Unknown enemyKey '{enemy_key}' in labyrinth[{record['id']}].floors[{floor_number}].fixedBattle"
                        )
                    level = int(enemy_entry["level"])
                    if level <= 0:
                        raise ValueError(
                            f"Expected labyrinth[{record['id']}].floors[{floor_number}].fixedBattle.enemy.level to be positive"
                        )
                    built_fixed_battle.append(
                        {
                            "enemyId": enemy_indices[enemy_key],
                            "level": level,
                        }
                    )
                if battle_count <= 0:
                    raise ValueError(
                        f"Expected labyrinth[{record['id']}].floors[{floor_number}].battleCount to be positive when fixedBattle exists"
                    )
                if len(built_fixed_battle) > enemy_count_cap:
                    raise ValueError(
                        f"Expected labyrinth[{record['id']}].floors[{floor_number}].fixedBattle to contain at most {enemy_count_cap} entries"
                    )

            random_battle_count = battle_count - (1 if built_fixed_battle is not None else 0)
            if random_battle_count > 0 and not encounters:
                raise ValueError(
                    f"Expected labyrinth[{record['id']}].floors[{floor_number}].encounters to be a non-empty array"
                )

            built_encounters: list[dict] = []
            for encounter in encounters:
                require_keys(
                    encounter,
                    ("enemyKey", "level", "weight"),
                    f"labyrinth[{record['id']}].floors[{floor_number}].encounter",
                )
                enemy_key = encounter["enemyKey"]
                if enemy_key not in enemy_indices:
                    raise ValueError(
                        f"Unknown enemyKey '{enemy_key}' in labyrinth[{record['id']}].floors[{floor_number}]"
                    )
                level = int(encounter["level"])
                if level <= 0:
                    raise ValueError(
                        f"Expected labyrinth[{record['id']}].floors[{floor_number}].encounter.level to be positive"
                    )
                built_encounters.append(
                    {
                        "enemyId": enemy_indices[enemy_key],
                        "level": level,
                        "weight": int(encounter["weight"]),
                    }
                )

            built_floors.append(
                {
                    "id": next_floor_id,
                    "floorNumber": floor_number,
                    "battleCount": battle_count,
                    "encounters": built_encounters,
                    "fixedBattle": built_fixed_battle,
                }
            )
            next_floor_id += 1

        labyrinths.append(
            {
                "id": labyrinth_index,
                "name": record["name"],
                "enemyCountCap": enemy_count_cap,
                "progressIntervalSeconds": int(record["progressIntervalSeconds"]),
                "floors": built_floors,
            }
        )
    return labyrinths


def build_runtime_master_data(source_dir: Path) -> dict:
    races = load_json(source_dir / "races.json")
    jobs = load_json(source_dir / "jobs.json")
    aptitudes = load_json(source_dir / "aptitudes.json")
    items = load_json(source_dir / "items.json")
    titles = load_json(source_dir / "titles.json")
    super_rares = load_json(source_dir / "superRares.json")
    skills = load_json(source_dir / "skills.json")
    spells = load_json(source_dir / "spells.json")
    names = load_json(source_dir / "names.json")
    enemies = load_json(source_dir / "enemies.json")
    labyrinths = load_json(source_dir / "labyrinths.json")

    for records, source_name in (
        (races, "races.json"),
        (jobs, "jobs.json"),
        (aptitudes, "aptitudes.json"),
        (items, "items.json"),
        (titles, "titles.json"),
        (super_rares, "superRares.json"),
        (skills, "skills.json"),
        (spells, "spells.json"),
        (enemies, "enemies.json"),
        (labyrinths, "labyrinths.json"),
    ):
        if not isinstance(records, list):
            raise ValueError(f"Expected top-level array in {source_name}")
        validate_unique_keys(records, source_name)

    if not isinstance(names, dict):
        raise ValueError("Expected top-level object in names.json")

    return {
        "metadata": {
            "generator": "generate_master_db.py",
        },
        "races": build_races(races, keyed_indices(skills)),
        "jobs": build_jobs(jobs, keyed_indices(skills)),
        "aptitudes": build_aptitudes(aptitudes, keyed_indices(skills)),
        "items": build_items(items, keyed_indices(skills)),
        "titles": build_titles(titles),
        "superRares": build_super_rares(super_rares, keyed_indices(skills)),
        "skills": build_skills(skills, keyed_indices(spells)),
        "spells": build_spells(spells),
        "recruitNames": build_recruit_names(names),
        "enemies": build_enemies(enemies, keyed_indices(jobs), keyed_indices(skills), keyed_indices(items)),
        "labyrinths": build_labyrinths(labyrinths, keyed_indices(enemies)),
    }


def write_runtime_master_data(source_dir: Path, output_path: Path):
    runtime_master_data = build_runtime_master_data(source_dir)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=output_path.parent,
        suffix=output_path.suffix,
        delete=False,
        mode="w",
        encoding="utf-8",
    ) as handle:
        json.dump(runtime_master_data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        temp_path = Path(handle.name)

    temp_path.replace(output_path)


def parse_args():
    parser = argparse.ArgumentParser(description="Generate bundled runtime master data JSON from JSON sources.")
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output-file", dest="output_path", type=Path)
    parser.add_argument("--output-db", dest="output_path", type=Path, help=argparse.SUPPRESS)
    return parser.parse_args()


def main():
    args = parse_args()
    if args.output_path is None:
        print("[master-generator] missing required argument: --output-file", file=sys.stderr)
        raise SystemExit(2)
    try:
        write_runtime_master_data(args.source_dir, args.output_path)
    except Exception as error:  # noqa: BLE001
        print(f"[master-generator] {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
