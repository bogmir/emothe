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
    field :digital_publication_date, :date
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
      :digital_publication_date,
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
      :authority
    ])
    |> validate_required([:title, :code])
    |> validate_inclusion(:language, @valid_languages)
    |> validate_number(:verse_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:code)
  end

  @doc """
  Changeset for manual form entry.
  """
  def form_changeset(play, attrs) do
    changeset(play, attrs)
  end
end
