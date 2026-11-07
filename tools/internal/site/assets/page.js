// The "Copy the prompt" button of the home page. It copies the text of the
// element that its data-copy attribute names. The page works without this
// script: the button stays hidden, and the text stays on the page.
(function () {
  "use strict";
  var button = document.querySelector("button.copy-prompt");
  var status = document.getElementById("copy-prompt-status");
  if (!button || !status || !navigator.clipboard) {
    return;
  }
  var source = document.getElementById(button.getAttribute("data-copy"));
  if (!source) {
    return;
  }
  var timer = 0;

  function say(text) {
    status.textContent = text;
    window.clearTimeout(timer);
    timer = window.setTimeout(function () { status.textContent = ""; }, 4000);
  }

  button.addEventListener("click", function () {
    navigator.clipboard.writeText(source.textContent)
      .then(function () { say("The prompt is on the clipboard."); })
      .catch(function () { say("The copy failed. Select the prompt and copy it."); });
  });
  button.hidden = false;
})();

// The "Copy as Markdown" button. The page works without this script: the
// button stays hidden, and the "View as Markdown" link gives the same text.
(function () {
  "use strict";
  var button = document.querySelector("button.copy-md");
  var status = document.getElementById("copy-md-status");
  if (!button || !status || !navigator.clipboard || !window.fetch) {
    return;
  }
  var timer = 0;

  function say(text) {
    status.textContent = text;
    window.clearTimeout(timer);
    timer = window.setTimeout(function () { status.textContent = ""; }, 4000);
  }

  button.addEventListener("click", function () {
    fetch(button.getAttribute("data-src"))
      .then(function (r) {
        if (!r.ok) {
          throw new Error(r.status);
        }
        return r.text();
      })
      .then(function (text) { return navigator.clipboard.writeText(text); })
      .then(function () { say("The Markdown of this page is on the clipboard."); })
      .catch(function () { say("The copy failed. Use \"View as Markdown\"."); });
  });
  button.hidden = false;
})();
