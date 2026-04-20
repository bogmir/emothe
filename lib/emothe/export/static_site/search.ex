defmodule Emothe.Export.StaticSite.Search do
  @moduledoc """
  Builds the search index and vanilla JS for the static site catalogue.
  """

  def build_index(plays) do
    plays
    |> Enum.map(fn play ->
      %{
        code: play.code,
        title: play.title,
        author: play.author_name,
        language: play.language,
        verse_count: play.verse_count,
        url: "plays/#{play.code}.html"
      }
    end)
    |> Jason.encode!(pretty: true)
  end

  def search_js do
    """
    (function() {
      'use strict';
      var input = document.getElementById('catalogue-search');
      var list = document.getElementById('catalogue-list');
      var countEl = document.getElementById('catalogue-count');
      var noResults = document.getElementById('no-results');
      if (!input || !list) return;

      var entries = list.querySelectorAll('.play-entry');
      var total = entries.length;

      input.addEventListener('input', function() {
        var q = input.value.toLowerCase().trim();
        var visible = 0;

        for (var i = 0; i < entries.length; i++) {
          var el = entries[i];
          if (!q) {
            el.style.display = '';
            visible++;
          } else {
            var title = el.getAttribute('data-title') || '';
            var author = el.getAttribute('data-author') || '';
            var code = el.getAttribute('data-code') || '';
            if (title.indexOf(q) !== -1 || author.indexOf(q) !== -1 || code.indexOf(q) !== -1) {
              el.style.display = '';
              visible++;
            } else {
              el.style.display = 'none';
            }
          }
        }

        if (countEl) {
          countEl.textContent = visible + ' of ' + total + ' plays';
        }
        if (noResults) {
          noResults.style.display = (visible === 0 && q) ? '' : 'none';
        }
      });
    })();
    """
  end
end
