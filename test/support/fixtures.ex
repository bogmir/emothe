defmodule Emothe.TestFixtures do
  alias Emothe.Catalogue
  alias Emothe.PlayContent
  alias Emothe.Places

  def unique_code, do: "PLAY-#{System.unique_integer([:positive])}"

  def play_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          "title" => "Play #{System.unique_integer([:positive])}",
          "code" => unique_code(),
          "title_sort" => "Play",
          "author_name" => "Author",
          "author_sort" => "Author",
          "language" => "es",
          "is_verse" => true
        },
        attrs
      )

    {:ok, play} = Catalogue.create_play(attrs)
    play
  end

  def play_with_metadata_fixture do
    play = play_fixture()

    {:ok, _} =
      Catalogue.create_play_source(%{
        play_id: play.id,
        title: "Source title",
        note: "Source note",
        position: 1
      })

    {:ok, _} =
      Catalogue.create_play_editor(%{
        play_id: play.id,
        person_name: "Editor One",
        role: "editor",
        position: 1
      })

    {:ok, _} =
      Catalogue.create_play_editorial_note(%{
        play_id: play.id,
        section_type: "nota",
        heading: "Editorial heading",
        content: "Editorial content",
        position: 1
      })

    Catalogue.get_play_with_all!(play.id)
  end

  @doc """
  Creates an original play with one derived translation linked via
  `parent_play_id`. Returns `%{original: original, translation: translation}`
  with both plays reloaded with associations.
  """
  def translation_family_fixture do
    original = play_fixture(%{"title" => "Original Play", "is_complete" => true})

    translation =
      play_fixture(%{
        "title" => "Translated Play",
        "parent_play_id" => original.id,
        "relationship_type" => "traduccion",
        "is_complete" => true
      })

    %{
      original: Catalogue.get_play_with_all!(original.id),
      translation: Catalogue.get_play_with_all!(translation.id)
    }
  end

  def play_with_structure_fixture do
    play = play_fixture(%{"title" => "Structured Play", "author_name" => "Tester"})

    {:ok, character} =
      PlayContent.create_character(%{
        play_id: play.id,
        xml_id: "ALFA",
        name: "ALFA",
        position: 1
      })

    {:ok, act} =
      PlayContent.create_division(%{
        play_id: play.id,
        type: "acto",
        number: 1,
        title: "ACT I",
        position: 1
      })

    {:ok, scene} =
      PlayContent.create_division(%{
        play_id: play.id,
        parent_id: act.id,
        type: "escena",
        number: 1,
        title: "SCENE I",
        position: 1
      })

    {:ok, speech} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        type: "speech",
        speaker_label: "ALFA",
        position: 1
      })

    PlayContent.set_element_characters(speech.id, [character.id])

    {:ok, line_group} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        parent_id: speech.id,
        type: "line_group",
        position: 1
      })

    {:ok, verse_line} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        parent_id: line_group.id,
        type: "verse_line",
        content: "A verse line",
        line_number: 1,
        part: "M",
        position: 1
      })

    {:ok, prose} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        parent_id: speech.id,
        type: "prose",
        content: "A prose fragment",
        position: 2
      })

    {:ok, stage_direction} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        type: "stage_direction",
        content: "A stage direction",
        position: 3
      })

    %{
      play: play,
      character: character,
      act: act,
      scene: scene,
      speech: speech,
      line_group: line_group,
      verse_line: verse_line,
      prose: prose,
      stage_direction: stage_direction
    }
  end

  @valid_user_password "verysecurepass123"

  def valid_user_password, do: @valid_user_password

  @doc """
  Inserts a user directly. Defaults to an active researcher.

  Accepts `:email`, `:role`, `:password`, `:confirmed_at`, `:deactivated_at`.
  Pass `confirmed_at: nil` for an unconfirmed user.
  """
  def user_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    %Emothe.Accounts.User{
      email: Map.get(attrs, :email, "user-#{System.unique_integer([:positive])}@example.com"),
      role: Map.get(attrs, :role, :researcher),
      confirmed_at: Map.get(attrs, :confirmed_at, DateTime.utc_now(:second)),
      deactivated_at: Map.get(attrs, :deactivated_at)
    }
    |> Emothe.Accounts.User.password_changeset(%{
      password: Map.get(attrs, :password, @valid_user_password)
    })
    |> Emothe.Repo.insert!()
  end

  def admin_fixture(attrs \\ %{}) do
    attrs |> Enum.into(%{}) |> Map.put(:role, :admin) |> user_fixture()
  end

  @doc """
  Creates an invited (password-less, unconfirmed) user.

  Returns `{user, raw_invite_token}`.
  """
  def invited_user_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    email = Map.get(attrs, :email, "invited-#{System.unique_integer([:positive])}@example.com")
    role = Map.get(attrs, :role, :researcher)

    {:ok, user, token} = Emothe.Accounts.invite_user(email, role, nil)
    {user, token}
  end

  @doc """
  A place with one or more names. `"name"` is shorthand for a single preferred
  Spanish name; pass `"names"` for the full list.
  """
  def place_fixture(attrs \\ %{}) do
    {name, attrs} = Map.pop(attrs, "name")

    names =
      Map.get(attrs, "names") ||
        [
          %{
            "name" => name || "Place #{System.unique_integer([:positive])}",
            "language" => "es",
            "is_preferred" => "true"
          }
        ]

    attrs =
      attrs
      |> Map.put_new("type", "city")
      |> Map.put("names", names)

    {:ok, place} = Places.create_place(attrs)
    place
  end

  def play_place_fixture(play, place, attrs \\ %{}) do
    {:ok, play_place} = Places.link_place(play.id, place.id, attrs)
    play_place
  end
end
