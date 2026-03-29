"""Tests generator validation and mapping rules for runtime master data."""

import json
import unittest
from pathlib import Path

from Generator.generate_master_db import (
    build_enemies,
    build_items,
    build_recruit_names,
    build_skills,
    build_super_rares,
    build_titles,
)


class BuildSkillsValidationTests(unittest.TestCase):
    def test_rejects_mul_on_battle_stat_modifier(self):
        records = [
            {
                "id": "skill-1",
                "name": "invalid stat mul",
                "description": "invalid",
                "effects": [
                    {
                        "kind": "battleStatModifier",
                        "target": "physicalAttack",
                        "operation": "mul",
                        "value": 1.5,
                    }
                ],
            }
        ]

        with self.assertRaisesRegex(ValueError, "Unsupported operation 'mul'"):
            build_skills(records, {})

    def test_rejects_operation_on_all_battle_stat_multiplier(self):
        records = [
            {
                "id": "skill-1",
                "name": "invalid all stat",
                "description": "invalid",
                "effects": [
                    {
                        "kind": "allBattleStatMultiplier",
                        "value": 1.5,
                        "operation": "mul",
                    }
                ],
            }
        ]

        with self.assertRaisesRegex(ValueError, "Unexpected key 'operation'"):
            build_skills(records, {})

    def test_accepts_valid_all_battle_stat_multiplier(self):
        records = [
            {
                "id": "skill-1",
                "name": "valid all stat",
                "description": "valid",
                "effects": [
                    {
                        "kind": "allBattleStatMultiplier",
                        "value": 1.5,
                    }
                ],
            }
        ]

        built = build_skills(records, {})

        self.assertEqual(
            built,
            [
                {
                    "id": 1,
                    "name": "valid all stat",
                    "description": "valid",
                    "effects": [
                        {
                            "kind": "allBattleStatMultiplier",
                            "target": None,
                            "operation": None,
                            "value": 1.5,
                            "spellIds": [],
                            "condition": None,
                            "interruptKind": None,
                        }
                    ],
                }
            ],
        )


class BuildTitlesTests(unittest.TestCase):
    def test_builds_titles_with_numeric_ids_and_weights(self):
        records = [
            {
                "id": "rough",
                "name": "粗末な",
                "positiveMultiplier": 0.5,
                "negativeMultiplier": 2.0,
                "dropWeight": 1024,
            },
            {
                "id": "untitled",
                "name": "",
                "positiveMultiplier": 1.0,
                "negativeMultiplier": 1.0,
                "dropWeight": 4096,
            },
        ]

        built = build_titles(records)

        self.assertEqual(
            built,
            [
                {
                    "id": 1,
                    "key": "rough",
                    "name": "粗末な",
                    "positiveMultiplier": 0.5,
                    "negativeMultiplier": 2.0,
                    "dropWeight": 1024,
                },
                {
                    "id": 2,
                    "key": "untitled",
                    "name": "",
                    "positiveMultiplier": 1.0,
                    "negativeMultiplier": 1.0,
                    "dropWeight": 4096,
                },
            ],
        )


class BuildRecruitNamesTests(unittest.TestCase):
    def test_builds_recruit_names_by_gender_key(self):
        built = build_recruit_names(
            {
                "male": ["アルド"],
                "female": ["リアナ"],
                "unisex": ["ノア"],
            }
        )

        self.assertEqual(
            built,
            {
                "male": ["アルド"],
                "female": ["リアナ"],
                "unisex": ["ノア"],
            },
        )


class BuildItemsTests(unittest.TestCase):
    def test_builds_items_with_numeric_ids_and_rarity(self):
        records = [
            {
                "id": "sword_normal_01",
                "name": "ショートソード",
                "category": "sword",
                "rarity": "normal",
                "basePrice": 120,
                "nativeBaseStats": {},
                "nativeBattleStats": {
                    "physicalAttack": 1,
                    "accuracy": 1,
                },
                "skillIds": ["physicalDamageMultiplier_plus_6pct"],
                "rangeClass": "melee",
                "normalDropTier": 1,
            },
            {
                "id": "jewel_godfiend_01",
                "name": "ダイヤモンド",
                "category": "jewel",
                "rarity": "godfiend",
                "basePrice": 11_000,
                "nativeBaseStats": {
                    "luck": 5,
                },
                "nativeBattleStats": {},
                "skillIds": [],
                "rangeClass": "none",
                "normalDropTier": 0,
                "normalDropTier": 0,
            },
        ]

        built = build_items(
            records,
            {
                "physicalDamageMultiplier_plus_6pct": 42,
            },
        )

        self.assertEqual(
            built,
            [
                {
                    "id": 1,
                    "name": "ショートソード",
                    "category": "sword",
                    "rarity": "normal",
                    "basePrice": 120,
                    "nativeBaseStats": {
                        "vitality": 0,
                        "strength": 0,
                        "mind": 0,
                        "intelligence": 0,
                        "agility": 0,
                        "luck": 0,
                    },
                    "nativeBattleStats": {
                        "maxHP": 0,
                        "physicalAttack": 1,
                        "physicalDefense": 0,
                        "magic": 0,
                        "magicDefense": 0,
                        "healing": 0,
                        "accuracy": 1,
                        "evasion": 0,
                        "attackCount": 0,
                        "criticalRate": 0,
                        "breathPower": 0,
                    },
                    "skillIds": [42],
                    "rangeClass": "melee",
                    "normalDropTier": 1,
                },
                {
                    "id": 2,
                    "name": "ダイヤモンド",
                    "category": "jewel",
                    "rarity": "godfiend",
                    "basePrice": 11000,
                    "nativeBaseStats": {
                        "vitality": 0,
                        "strength": 0,
                        "mind": 0,
                        "intelligence": 0,
                        "agility": 0,
                        "luck": 5,
                    },
                    "nativeBattleStats": {
                        "maxHP": 0,
                        "physicalAttack": 0,
                        "physicalDefense": 0,
                        "magic": 0,
                        "magicDefense": 0,
                        "healing": 0,
                        "accuracy": 0,
                        "evasion": 0,
                        "attackCount": 0,
                        "criticalRate": 0,
                        "breathPower": 0,
                    },
                    "skillIds": [],
                    "rangeClass": "none",
                    "normalDropTier": 0,
                },
            ],
        )

    def test_rejects_unsupported_rarity(self):
        records = [
            {
                "id": "broken_item",
                "name": "謎の石",
                "category": "jewel",
                "rarity": "legendary",
                "basePrice": 1,
                "nativeBaseStats": {},
                "nativeBattleStats": {},
                "skillIds": [],
                "rangeClass": "none",
                "normalDropTier": 0,
            }
        ]

        with self.assertRaisesRegex(ValueError, "Unsupported rarity 'legendary'"):
            build_items(records, {})

    def test_rejects_unexpected_sparse_stat_field(self):
        records = [
            {
                "id": "broken_item",
                "name": "謎の剣",
                "category": "sword",
                "rarity": "normal",
                "basePrice": 1,
                "nativeBaseStats": {"charisma": 3},
                "nativeBattleStats": {},
                "skillIds": [],
                "rangeClass": "melee",
                "normalDropTier": 1,
            }
        ]

        with self.assertRaisesRegex(ValueError, "Unexpected field\\(s\\) charisma"):
            build_items(records, {})


class BuildEnemiesTests(unittest.TestCase):
    def test_builds_enemies_with_reward_base_values(self):
        records = [
            {
                "id": "slime",
                "name": "スライム",
                "enemyRace": "monster",
                "jobKey": "fighter",
                "baseStats": {
                    "vitality": 1,
                    "strength": 2,
                    "mind": 3,
                    "intelligence": 4,
                    "agility": 5,
                    "luck": 6,
                },
                "goldBaseValue": 5,
                "experienceBaseValue": 5,
                "skillIds": [],
                "rareDropItemKeys": ["item-1"],
                "actionRates": {
                    "breath": 0,
                    "attack": 100,
                    "recoverySpell": 0,
                    "attackSpell": 0,
                },
                "actionPriority": ["attack", "attackSpell", "recoverySpell", "breath"],
            }
        ]

        built = build_enemies(records, {"fighter": 7}, {}, {"item-1": 11})

        self.assertEqual(
            built,
            [
                {
                    "id": 1,
                    "name": "スライム",
                    "enemyRace": "monster",
                    "jobId": 7,
                    "baseStats": {
                        "vitality": 1,
                        "strength": 2,
                        "mind": 3,
                        "intelligence": 4,
                        "agility": 5,
                        "luck": 6,
                    },
                    "goldBaseValue": 5,
                    "experienceBaseValue": 5,
                    "skillIds": [],
                    "rareDropItemIds": [11],
                    "actionRates": {
                        "breath": 0,
                        "attack": 100,
                        "recoverySpell": 0,
                        "attackSpell": 0,
                    },
                    "actionPriority": ["attack", "attackSpell", "recoverySpell", "breath"],
                }
            ],
        )


class BuildSuperRaresTests(unittest.TestCase):
    def test_builds_super_rares_with_numeric_ids_and_skill_ids(self):
        records = [
            {
                "id": "unveiled",
                "name": "暴かれし",
                "skillIds": ["skill-a", "skill-c"],
            },
            {
                "id": "hollow",
                "name": "虚ろなる",
                "skillIds": [],
            },
        ]

        built = build_super_rares(
            records,
            {
                "skill-a": 10,
                "skill-b": 20,
                "skill-c": 30,
            },
        )

        self.assertEqual(
            built,
            [
                {
                    "id": 1,
                    "name": "暴かれし",
                    "skillIds": [10, 30],
                },
                {
                    "id": 2,
                    "name": "虚ろなる",
                    "skillIds": [],
                },
            ],
        )

    def test_rejects_unknown_skill_id(self):
        records = [
            {
                "id": "unveiled",
                "name": "暴かれし",
                "skillIds": ["missing-skill"],
            }
        ]

        with self.assertRaisesRegex(ValueError, "Unknown skillId 'missing-skill'"):
            build_super_rares(records, {})


class GeneratedMasterDataOutputTests(unittest.TestCase):
    def test_generated_output_has_resolved_master_references(self):
        output_path = Path(__file__).resolve().parent / "Output" / "masterdata.json"
        self.assertTrue(output_path.exists(), output_path)

        master_data = json.loads(output_path.read_text())

        skill_ids = {entry["id"] for entry in master_data["skills"]}
        spell_ids = {entry["id"] for entry in master_data["spells"]}
        job_ids = {entry["id"] for entry in master_data["jobs"]}
        item_ids = {entry["id"] for entry in master_data["items"]}
        enemy_ids = {entry["id"] for entry in master_data["enemies"]}

        for race in master_data["races"]:
            self.assertTrue(set(race["skillIds"]).issubset(skill_ids))
        for job in master_data["jobs"]:
            self.assertTrue(set(job["skillIds"]).issubset(skill_ids))
        for item in master_data["items"]:
            self.assertTrue(set(item["skillIds"]).issubset(skill_ids))
        for super_rare in master_data["superRares"]:
            self.assertTrue(set(super_rare["skillIds"]).issubset(skill_ids))

        for enemy in master_data["enemies"]:
            self.assertIn(enemy["jobId"], job_ids)
            self.assertTrue(set(enemy["skillIds"]).issubset(skill_ids))
            self.assertTrue(set(enemy["rareDropItemIds"]).issubset(item_ids))

        for skill in master_data["skills"]:
            for effect in skill["effects"]:
                self.assertTrue(set(effect["spellIds"]).issubset(spell_ids))

        for labyrinth in master_data["labyrinths"]:
            floor_numbers = {floor["floorNumber"] for floor in labyrinth["floors"]}
            self.assertEqual(len(floor_numbers), len(labyrinth["floors"]))
            for floor in labyrinth["floors"]:
                self.assertGreater(floor["floorNumber"], 0)
                self.assertGreaterEqual(floor["battleCount"], 0)
                fixed_battle = floor.get("fixedBattle")
                random_battle_count = floor["battleCount"] - (1 if fixed_battle else 0)
                if random_battle_count > 0:
                    self.assertTrue(floor["encounters"])
                for encounter in floor["encounters"]:
                    self.assertIn(encounter["enemyId"], enemy_ids)
                    self.assertGreater(encounter["level"], 0)
                    self.assertGreater(encounter["weight"], 0)
                if fixed_battle:
                    self.assertTrue(fixed_battle)
                    self.assertTrue({entry["enemyId"] for entry in fixed_battle}.issubset(enemy_ids))
                    for entry in fixed_battle:
                        self.assertGreater(entry["level"], 0)


if __name__ == "__main__":
    unittest.main()
