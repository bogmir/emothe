defmodule Emothe.Places.PlayPlace do
  @moduledoc """
  A play's link to a place — the Phase 1 deliverable, a play-level place index.

  `role` distinguishes where the play is set from what it merely names; the FileMaker
  export encodes the same distinction with parentheses, `( Miseno )`. In-text mentions
  are Phase 2 and a different table.

  Carries `origin` because the TEI importer writes these rows: a re-import deletes only
  its own `"tei"` links and never touches a hand-entered one. Standing S0b rule.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(setting mentioned)

  def roles, do: @roles

  schema "play_places" do
    field :role, :string, default: "setting"
    field :position, :integer, default: 0
    field :note, :string
    field :origin, :string, default: "manual"

    belongs_to :play, Emothe.Catalogue.Play
    belongs_to :place, Emothe.Places.Place

    timestamps(type: :utc_datetime)
  end

  def changeset(play_place, attrs) do
    play_place
    |> cast(attrs, [:role, :position, :note, :origin, :play_id, :place_id])
    |> validate_required([:play_id, :place_id])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:origin, Emothe.Catalogue.origins())
    |> unique_constraint([:play_id, :place_id],
      error_key: :place_id,
      message: "is already linked to this play"
    )
    |> foreign_key_constraint(:place_id)
  end
end
