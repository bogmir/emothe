defmodule Emothe.Statistics.PlayStatistic do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "play_statistics" do
    field :data, :map, default: %{}
    field :computed_at, :utc_datetime

    belongs_to :play, Emothe.Catalogue.Play

    timestamps(type: :utc_datetime)
  end

  def changeset(statistic, attrs) do
    statistic
    |> cast(attrs, [:data, :computed_at, :play_id])
    |> validate_required([:data, :computed_at])
    |> unique_constraint(:play_id)
  end
end
