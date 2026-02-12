defmodule Emothe.PlayContent.Element do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "play_elements" do
    field :type, :string
    field :content, :string
    field :speaker_label, :string
    field :line_number, :integer
    field :line_id, :string
    field :verse_type, :string
    field :part, :string
    field :is_aside, :boolean, default: false
    field :rend, :string
    field :position, :integer, default: 0

    belongs_to :play, Emothe.Catalogue.Play
    belongs_to :division, Emothe.PlayContent.Division
    belongs_to :parent, __MODULE__
    belongs_to :character, Emothe.PlayContent.Character
    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  def changeset(element, attrs) do
    element
    |> cast(attrs, [
      :type,
      :content,
      :speaker_label,
      :line_number,
      :line_id,
      :verse_type,
      :part,
      :is_aside,
      :rend,
      :position,
      :play_id,
      :division_id,
      :parent_id,
      :character_id
    ])
    |> validate_required([:type])
    |> validate_inclusion(:type, ~w(speech stage_direction verse_line prose line_group))
  end
end
