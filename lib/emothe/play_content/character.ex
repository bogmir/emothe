defmodule Emothe.PlayContent.Character do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "characters" do
    field :xml_id, :string
    field :name, :string
    field :description, :string
    field :is_hidden, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :play, Emothe.Catalogue.Play
    has_many :element_characters, Emothe.PlayContent.ElementCharacter
    many_to_many :elements, Emothe.PlayContent.Element, join_through: Emothe.PlayContent.ElementCharacter

    timestamps(type: :utc_datetime)
  end

  def changeset(character, attrs) do
    character
    |> cast(attrs, [:xml_id, :name, :description, :is_hidden, :position, :play_id])
    |> validate_required([:xml_id, :name])
    |> unique_constraint([:play_id, :xml_id], error_key: :xml_id, message: "is already in use for this play")
  end
end
