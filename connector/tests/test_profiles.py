from __future__ import annotations

import pytest

from hermes_mobile_connector.profiles import (
    DEFAULT_PROFILE,
    locked_skills,
    normalize_profile,
    profile_home,
)


@pytest.mark.parametrize("raw", [None, "", "  "])
def test_empty_profile_means_default(raw):
    assert normalize_profile(raw) == DEFAULT_PROFILE


@pytest.mark.parametrize("raw", ["coach", "developer", "my-role_2"])
def test_valid_names_pass(raw):
    assert normalize_profile(raw) == raw


@pytest.mark.parametrize("raw", ["../x", "Coach", "-p", "a b", "x" * 65, "coach;rm"])
def test_invalid_names_are_rejected(raw):
    with pytest.raises(ValueError, match="^invalid:"):
        normalize_profile(raw)


def test_profile_home_resolves_default_and_named(tmp_path):
    (tmp_path / "profiles" / "coach").mkdir(parents=True)
    assert profile_home(tmp_path, None) == tmp_path
    assert profile_home(tmp_path, "default") == tmp_path
    assert profile_home(tmp_path, "coach") == tmp_path / "profiles" / "coach"


def test_profile_home_rejects_missing_profile(tmp_path):
    with pytest.raises(ValueError, match="^not_found:"):
        profile_home(tmp_path, "tutor")


def test_locked_skills_reads_auto_load(tmp_path):
    (tmp_path / "config.yaml").write_text("skills:\n  auto_load: [coach, weather-forecast]\n", encoding="utf-8")
    assert locked_skills(tmp_path) == frozenset({"coach", "weather-forecast"})


def test_locked_skills_tolerates_missing_config(tmp_path):
    assert locked_skills(tmp_path) == frozenset()
