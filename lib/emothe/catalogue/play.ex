defmodule Emothe.Catalogue.Play do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "plays" do
    field :title, :string
    field :title_sort, :string
    field :code, :string
    field :language, :string, default: "es"
    field :author_name, :string
    field :author_sort, :string
    field :author_attribution, :string
    field :publication_date, :string
    field :verse_count, :integer
    field :is_verse, :boolean, default: true
    field :publisher, :string
    field :pub_place, :string
    field :availability_note, :string
    field :project_description, :string
    field :editorial_declaration, :string
    field :original_title, :string
    field :licence_url, :string
    field :licence_text, :string
    field :emothe_id, :string
    field :sponsor, :string
    field :funder, :string
    field :authority, :string
    field :parent_play_id, :binary_id
    field :relationship_type, :string
    field :edition_title, :string
    field :is_complete, :boolean, default: false
    field :historical_time, :string
    field :historical_time_note, :string

    # Set only through Catalogue.delete_play/1 and restore_play/1 — deliberately absent
    # from every cast list so no form can archive a play.
    field :deleted_at, :utc_datetime

    belongs_to :parent_play, Emothe.Catalogue.Play, define_field: false
    has_many :derived_plays, Emothe.Catalogue.Play, foreign_key: :parent_play_id

    has_many :editors, Emothe.Catalogue.PlayEditor
    has_many :sources, Emothe.Catalogue.PlaySource
    has_many :editorial_notes, Emothe.Catalogue.PlayEditorialNote
    has_many :characters, Emothe.PlayContent.Character
    has_many :divisions, Emothe.PlayContent.Division
    has_many :elements, Emothe.PlayContent.Element
    has_one :statistic, Emothe.Statistics.PlayStatistic

    timestamps(type: :utc_datetime)
  end

  @valid_languages ~w(es en it ca fr pt)

  def valid_languages, do: @valid_languages

  @language_names %{
    "es" => "Español",
    "en" => "English",
    "it" => "Italiano",
    "ca" => "Català",
    "fr" => "Français",
    "pt" => "Português"
  }

  def language_name(code), do: Map.get(@language_names, code, code)

  # FileMaker bus_tiemHistorico codes, recovered by pairing the code against the rendered
  # label across all 439 rows of the export. Codes 3 and 4 do not occur.
  #   1 tiempo_indeterminado   2 antiguo_testamento   5 edad_media
  #   6 siglo_xv               7 siglo_xvi            8 siglo_xvii
  #   9 tiempo_maravilloso    10 antiguedad_clasica  11 tiempo_alegorico
  @historical_times ~w(
    tiempo_indeterminado antiguo_testamento edad_media siglo_xv siglo_xvi
    siglo_xvii tiempo_maravilloso antiguedad_clasica tiempo_alegorico
  )

  def historical_times, do: @historical_times

  def changeset(play, attrs) do
    play
    |> cast(attrs, [
      :title,
      :title_sort,
      :code,
      :language,
      :author_name,
      :author_sort,
      :author_attribution,
      :publication_date,
      :verse_count,
      :is_verse,
      :publisher,
      :pub_place,
      :availability_note,
      :project_description,
      :editorial_declaration,
      :original_title,
      :licence_url,
      :licence_text,
      :emothe_id,
      :sponsor,
      :funder,
      :authority,
      :parent_play_id,
      :relationship_type,
      :edition_title,
      :is_complete,
      :historical_time,
      :historical_time_note
    ])
    |> validate_required([:title, :code])
    |> validate_inclusion(:language, @valid_languages)
    |> validate_number(:verse_count, greater_than_or_equal_to: 0)
    |> validate_inclusion(:relationship_type, ~w(traduccion adaptacion refundicion))
    |> validate_inclusion(:historical_time, @historical_times)
    |> unique_constraint(:code)
  end

  @doc """
  Changeset for manual form entry.
  """
  def form_changeset(play, attrs) do
    changeset(play, attrs)
  end
end
