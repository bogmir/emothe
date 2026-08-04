defmodule Emothe.Places.PlaceName do
  @moduledoc """
  One surface form of a place, tagged with a language.

  `İstanbul`, `Constantinopla`, `Constantinople` and `Bizancio` are four of these on
  one place. `is_preferred` is unique per place **per language**, enforced by a partial
  index, so a Spanish UI can prefer `Roma` while an English one prefers `Rome`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "place_names" do
    field :name, :string
    field :language, :string
    field :is_preferred, :boolean, default: false
    field :is_historical, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :place, Emothe.Places.Place

    timestamps(type: :utc_datetime)
  end

  def changeset(place_name, attrs) do
    place_name
    |> cast(attrs, [:name, :language, :is_preferred, :is_historical, :position, :place_id])
    |> validate_required([:name])
    |> unique_constraint(:is_preferred,
      name: :one_preferred_name_per_place_and_language,
      message: "another name is already preferred for this language"
    )
  end
end
