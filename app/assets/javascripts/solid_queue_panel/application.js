// Solid Queue Panel — everything the dashboard needs on the client, which
// is not much: live refresh of the current page, bulk selection and confirm
// dialogs. No framework, no build step, no external requests.
(function () {
  "use strict";

  var POLL_STORAGE_KEY = "solid-queue-panel:polling";
  var POLL_REGION = "[data-sqp-poll]";

  function readPollingPreference() {
    try {
      return window.localStorage.getItem(POLL_STORAGE_KEY) !== "off";
    } catch (error) {
      return true;
    }
  }

  function writePollingPreference(enabled) {
    try {
      window.localStorage.setItem(POLL_STORAGE_KEY, enabled ? "on" : "off");
    } catch (error) {
      // Private browsing and friends: the preference simply does not stick.
    }
  }

  // Refreshing while someone is picking jobs or typing would throw their work
  // away, so the poller waits for them to be done.
  function busy() {
    var active = document.activeElement;

    if (active && (active.tagName === "INPUT" || active.tagName === "TEXTAREA" || active.tagName === "SELECT")) {
      return active.type !== "checkbox";
    }

    return document.querySelector("input[type=checkbox][data-sqp-bulk-item]:checked") !== null;
  }

  function Poller(region) {
    this.region = region;
    this.interval = parseInt(region.getAttribute("data-sqp-poll"), 10) || 0;
    this.enabled = this.interval > 0 && readPollingPreference();
    this.timer = null;
  }

  Poller.prototype.start = function () {
    this.stop();
    if (!this.enabled) return;

    this.timer = window.setTimeout(this.tick.bind(this), this.interval * 1000);
  };

  Poller.prototype.stop = function () {
    if (this.timer) window.clearTimeout(this.timer);
    this.timer = null;
  };

  Poller.prototype.tick = function () {
    var poller = this;

    if (document.hidden || busy()) {
      poller.start();
      return;
    }

    window
      .fetch(window.location.href, { headers: { "X-Requested-With": "XMLHttpRequest" }, credentials: "same-origin" })
      .then(function (response) {
        // The session expired while the page was sitting there: reload so the
        // sign in form comes up instead of stale data.
        if (response.status === 401) window.location.reload();

        return response.ok ? response.text() : Promise.reject(response.status);
      })
      .then(function (html) {
        var fresh = new DOMParser().parseFromString(html, "text/html").querySelector(POLL_REGION);
        if (fresh) {
          poller.region.innerHTML = fresh.innerHTML;
          poller.region.dispatchEvent(new CustomEvent("sqp:refreshed", { bubbles: true }));
        }
      })
      .catch(function () {
        // A failed refresh is not worth interrupting anyone over: try again on
        // the next tick.
      })
      .then(function () {
        poller.start();
      });
  };

  Poller.prototype.toggle = function () {
    this.enabled = !this.enabled;
    writePollingPreference(this.enabled);
    this.enabled ? this.start() : this.stop();
    this.render();
  };

  Poller.prototype.render = function () {
    var buttons = document.querySelectorAll("[data-sqp-poll-toggle]");

    for (var index = 0; index < buttons.length; index++) {
      var button = buttons[index];
      button.setAttribute("aria-pressed", String(this.enabled));
      button.querySelector("[data-sqp-poll-label]").textContent = this.enabled ? "Live" : "Paused";
      button.querySelector("[data-sqp-poll-dot]").classList.toggle("animate-pulse", this.enabled);
      button.querySelector("[data-sqp-poll-dot]").classList.toggle("bg-emerald-500", this.enabled);
      button.querySelector("[data-sqp-poll-dot]").classList.toggle("bg-slate-400", !this.enabled);
    }
  };

  function setUpPolling() {
    var region = document.querySelector(POLL_REGION);
    if (!region) return;

    var poller = new Poller(region);
    poller.render();
    poller.start();

    document.addEventListener("click", function (event) {
      var toggle = event.target.closest("[data-sqp-poll-toggle]");
      if (toggle) {
        event.preventDefault();
        poller.toggle();
      }
    });

    document.addEventListener("visibilitychange", function () {
      document.hidden ? poller.stop() : poller.start();
    });
  }

  // "Select all" checkbox of the bulk action bars.
  function setUpBulkSelection() {
    document.addEventListener("change", function (event) {
      var master = event.target.closest("[data-sqp-bulk-all]");
      if (!master) return;

      var form = master.closest("form");
      var items = form.querySelectorAll("[data-sqp-bulk-item]");

      for (var index = 0; index < items.length; index++) {
        items[index].checked = master.checked;
      }
    });
  }

  // Copies a page's plain text version to the clipboard. The text is fetched
  // when the button is clicked, so building it costs nothing until someone
  // wants it.
  function setUpCopyButtons() {
    document.addEventListener("click", function (event) {
      var button = event.target.closest("[data-sqp-copy]");
      if (!button) return;

      event.preventDefault();

      window
        .fetch(button.getAttribute("data-sqp-copy"), { credentials: "same-origin" })
        .then(function (response) {
          return response.ok ? response.text() : Promise.reject(response.status);
        })
        .then(copyToClipboard)
        .then(function () {
          flashLabel(button, "Copied");
        })
        .catch(function () {
          flashLabel(button, "Copy failed");
        });
    });
  }

  // The asynchronous clipboard is only available over HTTPS and on localhost,
  // and panels are often mounted on plain HTTP inside a private network. It can
  // also be refused when the browser does not consider the click recent enough,
  // so the older way to copy is both the fallback and the second chance.
  function copyToClipboard(text) {
    if (window.navigator.clipboard && window.isSecureContext) {
      return window.navigator.clipboard.writeText(text).catch(function () {
        return copyThroughSelection(text);
      });
    }

    return copyThroughSelection(text);
  }

  function copyThroughSelection(text) {
    return new Promise(function (resolve, reject) {
      var area = document.createElement("textarea");

      area.value = text;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.top = "-1000px";
      area.style.opacity = "0";

      document.body.appendChild(area);
      area.select();

      var copied = document.execCommand("copy");
      document.body.removeChild(area);

      copied ? resolve() : reject(new Error("copy refused"));
    });
  }

  function flashLabel(button, message) {
    var label = button.querySelector("[data-sqp-copy-label]") || button;

    if (!label.dataset.originalLabel) label.dataset.originalLabel = label.textContent;
    label.textContent = message;

    window.setTimeout(function () {
      label.textContent = label.dataset.originalLabel;
    }, 2000);
  }

  // Confirmations without depending on Turbo or Rails UJS being loaded.
  function setUpConfirmations() {
    document.addEventListener("submit", function (event) {
      var message = event.target.getAttribute("data-sqp-confirm");

      if (message && !window.confirm(message)) {
        event.preventDefault();
      }
    });
  }

  function boot() {
    setUpPolling();
    setUpBulkSelection();
    setUpConfirmations();
    setUpCopyButtons();
  }

  document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", boot) : boot();
})();
