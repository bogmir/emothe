defmodule Playcode.Import.TeiCorpusTest do
  # Which file stands for each code when the corpus spans directories. Importing them
  # is asserted through `mix playcode.import.tei` in test/mix/tasks_test.exs.
  use Playcode.DataCase, async: true

  alias Playcode.Import.TeiCorpus

  defp tmp_dir(name) do
    dir = Path.join(System.tmp_dir!(), "corpus-#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  describe "collect_files/1" do
    test "returns one path per code, sorted, with the first directory winning" do
      first = tmp_dir("first")
      second = tmp_dir("second")

      File.write!(Path.join(first, "EMOTHE0038_AntonyAndCleopatra.xml"), "<TEI/>")
      File.write!(Path.join(second, "EMOTHE0038_AntonyAndCleopatra.xml"), "<TEI/>")
      File.write!(Path.join(second, "AL0514_ElAusenteEnElLugar.xml"), "<TEI/>")

      assert [{"AL0514", al_path}, {"EMOTHE0038", playcode_path}] =
               TeiCorpus.collect_files([first, second])

      assert al_path == Path.join(second, "AL0514_ElAusenteEnElLugar.xml")
      assert playcode_path == Path.join(first, "EMOTHE0038_AntonyAndCleopatra.xml")
    end

    test "ignores non-xml files and missing directories" do
      dir = tmp_dir("mixed")
      File.write!(Path.join(dir, "notes.txt"), "hello")
      File.write!(Path.join(dir, "EMOTHE0050_Amleto.xml"), "<TEI/>")

      assert [{"EMOTHE0050", _}] = TeiCorpus.collect_files([dir, "/nonexistent/path"])
    end
  end
end
