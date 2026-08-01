defmodule Emothe.Import.TeiCorpusTest do
  use Emothe.DataCase, async: true

  alias Emothe.Import.TeiCorpus

  defp tmp_dir(name) do
    dir = Path.join(System.tmp_dir!(), "corpus-#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  describe "base_code/1" do
    test "takes the leading token of a filename stem" do
      assert TeiCorpus.base_code("EMOTHE0010_TheTragedyOfHamletPrinceOfDenmark") == "EMOTHE0010"
      assert TeiCorpus.base_code("AL0514") == "AL0514"
    end
  end

  describe "collect_files/1" do
    test "returns one path per code, sorted, with the first directory winning" do
      first = tmp_dir("first")
      second = tmp_dir("second")

      File.write!(Path.join(first, "EMOTHE0038_AntonyAndCleopatra.xml"), "<TEI/>")
      File.write!(Path.join(second, "EMOTHE0038_AntonyAndCleopatra.xml"), "<TEI/>")
      File.write!(Path.join(second, "AL0514_ElAusenteEnElLugar.xml"), "<TEI/>")

      assert [{"AL0514", al_path}, {"EMOTHE0038", emothe_path}] =
               TeiCorpus.collect_files([first, second])

      assert al_path == Path.join(second, "AL0514_ElAusenteEnElLugar.xml")
      assert emothe_path == Path.join(first, "EMOTHE0038_AntonyAndCleopatra.xml")
    end

    test "ignores non-xml files and missing directories" do
      dir = tmp_dir("mixed")
      File.write!(Path.join(dir, "notes.txt"), "hello")
      File.write!(Path.join(dir, "EMOTHE0050_Amleto.xml"), "<TEI/>")

      assert [{"EMOTHE0050", _}] = TeiCorpus.collect_files([dir, "/nonexistent/path"])
    end
  end

  describe "import_all/2" do
    @minimal_tei """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI>
      <teiHeader>
        <fileDesc>
          <titleStmt>
            <title key="archivo">EMOTHE9001_TestPlay</title>
            <title>Test Play</title>
          </titleStmt>
          <publicationStmt><idno>EMOTHE9001</idno></publicationStmt>
        </fileDesc>
      </teiHeader>
      <text><front></front><body></body></text>
    </TEI>
    """

    test "imports a file once and skips it on a second run" do
      dir = tmp_dir("import")
      File.write!(Path.join(dir, "EMOTHE9001_TestPlay.xml"), @minimal_tei)
      files = TeiCorpus.collect_files([dir])

      assert [{:ok, "EMOTHE9001", play}] = TeiCorpus.import_all(files)
      assert play.code == "EMOTHE9001_TestPlay"

      assert [{:skipped, "EMOTHE9001"}] = TeiCorpus.import_all(files)
    end
  end
end
