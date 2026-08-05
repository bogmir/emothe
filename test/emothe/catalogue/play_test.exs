defmodule Emothe.Catalogue.PlayTest do
  use ExUnit.Case, async: true

  alias Emothe.Catalogue.Play

  defp changeset(attrs) do
    Play.changeset(%Play{}, Map.merge(%{"title" => "Test", "code" => "TEST01"}, attrs))
  end

  test "accepts a year range" do
    cs = changeset(%{"composition_date_from" => "1606", "composition_date_to" => "1607"})

    assert cs.valid?
    assert cs.changes.composition_date_from == 1606
    assert cs.changes.composition_date_to == 1607
  end

  test "accepts a single year as from == to" do
    cs = changeset(%{"composition_date_from" => "1614", "composition_date_to" => "1614"})

    assert cs.valid?
  end

  test "accepts a note with no years" do
    cs = changeset(%{"composition_date_note" => "alrededor de 1601"})

    assert cs.valid?
  end

  test "rejects a lone start year" do
    cs = changeset(%{"composition_date_from" => "1606"})

    refute cs.valid?
    assert {"must be given together with the end year", _} = cs.errors[:composition_date_from]
  end

  test "rejects a lone end year" do
    cs = changeset(%{"composition_date_to" => "1607"})

    refute cs.valid?
    assert {"must be given together with the start year", _} = cs.errors[:composition_date_to]
  end

  test "rejects an end year before the start year" do
    cs = changeset(%{"composition_date_from" => "1607", "composition_date_to" => "1606"})

    refute cs.valid?
    assert {"must not be before the start year", _} = cs.errors[:composition_date_to]
  end

  test "rejects a year outside the plausible range" do
    cs = changeset(%{"composition_date_from" => "160", "composition_date_to" => "160"})

    refute cs.valid?
    assert cs.errors[:composition_date_from]
  end
end
