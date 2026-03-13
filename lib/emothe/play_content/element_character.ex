defmodule Emothe.PlayContent.ElementCharacter do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "element_characters" do
    belongs_to :element, Emothe.PlayContent.Element
    belongs_to :character, Emothe.PlayContent.Character
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(element_character, attrs) do
    element_character
    |> cast(attrs, [:element_id, :character_id, :position])
    |> validate_required([:element_id, :character_id])
    |> unique_constraint([:element_id, :character_id])
  end
end
