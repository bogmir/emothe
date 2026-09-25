defmodule RenameGuardTest do
  @moduledoc """
  Guards the 2026-09-21 `Emothe` -> `Playcode` rename.

  Three different things in this repository are spelled some form of "emothe",
  and only one of them was ours to rename:

    * `Emothe` / `emothe` — the application's own identity: the module
      namespace, the `:emothe` OTP app, the lib/ and test/ trees, the database
      names, the mix tasks. Renamed.
    * `EMOTHE` — the corpus and the public brand: the play codes that identify
      every play (`EMOTHE0010`), the TEI fixture filenames, the UI copy. The
      application was renamed; the corpus was not. Untouched.
    * `emothe.uv.es` — the project's real domain, in licence URLs and the
      `MAIL_FROM` default. Untouched.

  Plus one third-party string: `"emothe"` inside
  `test/fixtures/filemaker/*.ndjson` is the *FileMaker export's own table
  name*, mirroring the real external system. Untouched.

  This file stays in the tree permanently. A future careless search-and-replace
  should fail here loudly rather than silently rewrite play codes.

  Note on scanning: source cleanliness is checked with `git grep`, because
  untracked files are not our source. Corpus protection is checked against the
  *filesystem*, because `test/fixtures/tei_files/` is git-ignored and a `perl`
  sweep does not care what git tracks.
  """
  use ExUnit.Case, async: true

  @repo_root Path.expand("..", __DIR__)
  @bulk_fixtures Path.expand("fixtures/tei_files", __DIR__)

  # Ours. Must be clean of the old application identity.
  @scanned ~w(
    lib test config mix.exs assets priv/repo priv/gettext
    .github Dockerfile Dockerfile.render fly.toml render.yaml entrypoint.sh
  )

  # Corpus data, third-party samples, the legacy Fly config that is *supposed*
  # to still say "emothe", and this test, which names the old identity on
  # purpose.
  @excluded ~w(test/fixtures test/rename_guard_test.exs fly.emothe.toml)

  describe "the new namespace" do
    # Module names are built with Module.concat/1 rather than written as
    # literal aliases. Before the rename the new modules do not exist and after
    # it the old ones do not, and a literal alias to a missing module is a
    # compiler warning — which `mix compile --warnings-as-errors` turns into a
    # build failure.

    test "Playcode modules are the ones that exist" do
      assert Code.ensure_loaded?(Module.concat(["Playcode", "Catalogue"]))
      assert Code.ensure_loaded?(Module.concat(["Playcode", "Repo"]))
      assert Code.ensure_loaded?(Module.concat(["PlaycodeWeb", "Endpoint"]))
    end

    test "the old namespace is gone" do
      refute Code.ensure_loaded?(Module.concat(["Emothe", "Catalogue"]))
      refute Code.ensure_loaded?(Module.concat(["EmotheWeb", "Endpoint"]))
    end

    test "the OTP application is :playcode" do
      assert Application.get_application(Module.concat(["Playcode", "Catalogue"])) == :playcode

      assert Application.fetch_env!(:playcode, :ecto_repos) == [
               Module.concat(["Playcode", "Repo"])
             ]
    end
  end

  describe "the corpus keeps its identity" do
    test "the tracked TEI fixtures are still named for their play codes" do
      names =
        git!(["ls-files", "test/fixtures"])
        |> String.split("\n", trim: true)
        |> Enum.filter(&Regex.match?(~r|^test/fixtures/EMOTHE\d{4}_.*\.xml$|, &1))

      assert length(names) == 55,
             "expected 55 tracked EMOTHE####_*.xml fixtures, found #{length(names)}"
    end

    test "the git-ignored bulk fixtures still carry EMOTHE play codes" do
      # test/fixtures/tei_files/ is git-ignored, so a fresh clone does not have
      # it. Guarded the same way roundtrip_test.exs guards the same directory.
      if File.dir?(@bulk_fixtures) and File.ls!(@bulk_fixtures) != [] do
        assert disk_grep("EMOTHE[0-9]{4}", ["test/fixtures/tei_files"]) != [],
               "the bulk TEI fixtures are present but no longer contain EMOTHE play codes"
      end
    end

    test "no play code anywhere was rewritten to the new name" do
      # The sharpest check in this file. It does not depend on any fixture
      # being present, and it catches the exact failure mode a blanket
      # search-and-replace produces.
      assert disk_grep("PLAYCODE[0-9]{4}", ["lib", "test", "priv", "docs", "config"]) == [],
             "a play code was rewritten — EMOTHE#### is corpus data, not the application name"
    end

    test "the public EMOTHE brand is still in the Spanish UI copy" do
      po = File.read!(Path.join(@repo_root, "priv/gettext/es/LC_MESSAGES/default.po"))

      brand_strings =
        po
        |> String.split("\n")
        |> Enum.filter(&(String.starts_with?(&1, "msgid ") or String.starts_with?(&1, "msgstr ")))
        |> Enum.filter(&String.contains?(&1, "EMOTHE"))

      assert length(brand_strings) == 12,
             "expected 12 EMOTHE brand strings in the Spanish catalogue, found #{length(brand_strings)}"

      assert po =~ ~s(msgstr "Biblioteca Digital EMOTHE")
    end

    test "emothe.uv.es is untouched" do
      runtime = File.read!(Path.join(@repo_root, "config/runtime.exs"))
      assert runtime =~ "noreply@emothe.uv.es"
    end

    test "the FileMaker fixtures still name the export's own database" do
      sample = File.read!(Path.join(@repo_root, "test/fixtures/filemaker/index_sample.ndjson"))

      assert sample =~ ~s("w3emothe"),
             ~s(the FileMaker export names its own database "w3emothe"; renaming it falsifies the fixture)
    end

    test "the real FileMaker export path is still w3emothe" do
      # lib/.../import/filemaker.ex defaults to doc/w3emothe_T01_tituloEM.ndjson,
      # which is the name of the actual file on disk. Renaming that string to
      # w3playcode breaks the import silently — nothing fails to compile, the
      # file just stops being found.
      assert disk_grep("w3emothe_T01_tituloEM\\.ndjson", ["lib"]) != [],
             "the default FileMaker export path no longer names w3emothe"
    end

    test "the plays.emothe_id column keeps its corpus name" do
      # plays.emothe_id holds the EMOTHE project's identifier for a play. It is
      # corpus vocabulary, like the play code, not the application's name, and
      # it is a real column in a real database.
      migration =
        File.read!(
          Path.join(
            @repo_root,
            "priv/repo/migrations/20260220095242_add_extended_metadata_fields.exs"
          )
        )

      assert migration =~ "add :emothe_id, :string"
      assert disk_grep("field :emothe_id", ["lib"]) != [], "the schema lost its :emothe_id field"
    end
  end

  describe "no stale application identity in our own source" do
    test "nothing references the Emothe module namespace" do
      assert git_grep(~S(\bEmothe)) == []
    end

    test "nothing references the emothe app name" do
      # The exceptions are not the application. Each is domain or third-party
      # vocabulary that outlived the rename:
      #
      #   emothe.uv.es                 the project's real domain
      #   w3emothe                     the FileMaker export's own database
      #   emothe_id / emothe_idno      plays.emothe_id, a real column holding
      #                                the EMOTHE identifier for a play
      #   emothe_project_description   the EMOTHE project's own blurb
      #   emothe-static                the published EMOTHE site: the example
      #                                GitHub repo in the deploy form and the
      #                                name of the .zip a researcher downloads
      assert git_grep(~S{(?<!w3)emothe(?!\.uv\.es|_id|_project_description|-static)}) == []
    end
  end

  # Tracked files only: untracked files are not our source.
  defp git_grep(pattern) do
    args =
      ["grep", "--no-color", "-l", "-P", pattern, "--"] ++
        @scanned ++ Enum.map(@excluded, &(":(exclude)" <> &1))

    case System.cmd("git", args, cd: @repo_root, stderr_to_stdout: true) do
      # git grep exits 1 when it finds nothing, which is the passing case.
      {_, 1} -> []
      {out, 0} -> String.split(String.trim(out), "\n", trim: true)
    end
  end

  # The filesystem, git-ignored files included.
  defp disk_grep(pattern, paths) do
    args =
      [
        "-rIlE",
        pattern,
        "--exclude-dir=.git",
        "--exclude-dir=_build",
        "--exclude-dir=deps",
        "--exclude-dir=node_modules",
        "--exclude=rename_guard_test.exs",
        # The rename plan quotes PLAYCODE0010 as the example of a corrupted
        # play code, so it would match the sentinel scan it describes.
        "--exclude=2026-09-21-rename-emothe-to-playcode.md"
      ] ++ paths

    case System.cmd("grep", args, cd: @repo_root, stderr_to_stdout: true) do
      {_, 1} -> []
      {out, 0} -> String.split(String.trim(out), "\n", trim: true)
    end
  end

  defp git!(args) do
    {out, _} = System.cmd("git", args, cd: @repo_root, stderr_to_stdout: true)
    out
  end
end
