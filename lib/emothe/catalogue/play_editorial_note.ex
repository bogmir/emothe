defmodule Emothe.Catalogue.PlayEditorialNote do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "play_editorial_notes" do
    field :section_type, :string
    field :heading, :string
    field :content, :string
    field :position, :integer, default: 0

    belongs_to :play, Emothe.Catalogue.Play

    timestamps(type: :utc_datetime)
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:section_type, :heading, :content, :position, :play_id])
    |> validate_required([:section_type, :content])
    |> validate_inclusion(
      :section_type,
      ~w(introduccion_editor dedicatoria argumento prologo nota)
    )
  end
end
