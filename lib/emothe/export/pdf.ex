defmodule Emothe.Export.Pdf do
  @moduledoc """
  Generates PDF from a play using ChromicPDF (headless Chrome).
  Reuses the HTML export for identical styling to the public play page.
  """

  alias Emothe.Export.Html

  def generate(play) do
    html = Html.generate(play)

    case ChromicPDF.print_to_pdf({:html, html},
           print_to_pdf: %{
             marginTop: 0.6,
             marginBottom: 0.6,
             marginLeft: 0.8,
             marginRight: 0.8
           }
         ) do
      {:ok, blob} -> {:ok, Base.decode64!(blob)}
      {:error, reason} -> {:error, reason}
    end
  end
end
