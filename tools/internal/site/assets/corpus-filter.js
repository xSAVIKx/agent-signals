// The facet filter of the corpus page. The page works without this script:
// the form stays hidden and the tables show all screens.
(function () {
  "use strict";
  var form = document.getElementById("corpus-filter-box");
  var status = document.getElementById("corpus-filter-status");
  var fieldset = form && form.querySelector("fieldset");
  if (!form || !status || !fieldset) {
    return;
  }
  var selects = Array.prototype.slice.call(form.querySelectorAll("select[data-facet]"));
  var rows = Array.prototype.slice.call(document.querySelectorAll("tr[data-agent]"));
  var blocks = Array.prototype.slice.call(document.querySelectorAll("section.agent-block"));
  var tocItems = Array.prototype.slice.call(document.querySelectorAll("#corpus-toc li"));

  function readQuery() {
    var params = new URLSearchParams(window.location.search);
    selects.forEach(function (sel) {
      // An exact match wins. Else the match ignores case, so ?state=trust
      // selects TRUST. Two options can differ only in case, for example
      // the versions 1.0.0-RC1 and 1.0.0-rc1: the exact match keeps the
      // value that the page wrote. A value that is not an option leaves
      // the select on "All".
      var raw = params.get(sel.dataset.facet) || "";
      var want = raw.toLowerCase();
      var exact = "";
      var folded = "";
      Array.prototype.forEach.call(sel.options, function (o) {
        if (!raw) {
          return;
        }
        if (o.value === raw) {
          exact = o.value;
        } else if (!folded && o.value.toLowerCase() === want) {
          folded = o.value;
        }
      });
      sel.value = exact || folded;
    });
  }

  function writeQuery() {
    var params = new URLSearchParams();
    selects.forEach(function (sel) {
      if (sel.value) {
        params.set(sel.dataset.facet, sel.value);
      }
    });
    var query = params.toString();
    var url = window.location.pathname + (query ? "?" + query : "") + window.location.hash;
    window.history.replaceState(null, "", url);
  }

  function apply() {
    var shown = 0;
    var perAgent = {};
    rows.forEach(function (row) {
      var match = selects.every(function (sel) {
        return !sel.value || row.dataset[sel.dataset.facet] === sel.value;
      });
      row.hidden = !match;
      if (match) {
        shown += 1;
        perAgent[row.dataset.agent] = true;
      }
    });
    blocks.forEach(function (block) {
      block.hidden = !perAgent[block.dataset.agent];
    });
    tocItems.forEach(function (item) {
      item.hidden = !perAgent[item.dataset.agent];
    });
    status.textContent = shown + " of " + rows.length + " screens shown.";
  }

  selects.forEach(function (sel) {
    sel.addEventListener("change", function () {
      apply();
      writeQuery();
    });
  });
  form.addEventListener("submit", function (e) { e.preventDefault(); });
  form.addEventListener("reset", function () {
    // The reset event fires before the controls change. Wait one task.
    window.setTimeout(function () {
      apply();
      writeQuery();
    }, 0);
  });
  window.addEventListener("popstate", function () {
    readQuery();
    apply();
  });

  readQuery();
  apply();
  form.hidden = false;
  // The controls stay disabled until the handlers are in place and the
  // query of the URL is applied. A choice before that would be lost.
  fieldset.disabled = false;
})();
