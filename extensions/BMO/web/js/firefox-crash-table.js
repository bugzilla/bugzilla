/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/**
 * Embed a crash data table on Firefox bugs.
 * Original code: https://github.com/mozilla/crash-stop-addon/blob/master/webextension/content.js
 */
window.addEventListener('DOMContentLoaded', () => {
  "use strict";

  const VERSION = "0.3.1";

  async function fetchProductDetails() {
    const url = "https://product-details.mozilla.org/1.0/firefox_versions.json";
    const response = await fetch(url);
    return await response.json();
  }

  function getMajorFromSF(s) {
    // cf_status_firefox** or cf_status_firefox_esr**
    const cf = "cf_status_firefox";
    const esr = "_esr";
    const last = s.slice(cf.length);
    if (last.startsWith(esr)) {
      return {esr: true,
              version: parseInt(last.slice(esr.length), 10)};
    }
    return {esr: false,
            version: parseInt(last, 10)};
  }

  function getMajor(s) {
    return parseInt(s.split(".")[0], 10);
  }

  function getMajors(pd) {
    // { FIREFOX_NIGHTLY: "61.0a1",
    //   FIREFOX_AURORA: "",
    //   FIREFOX_ESR: "52.7.3esr",
    //   FIREFOX_ESR_NEXT: "",
    //   LATEST_FIREFOX_DEVEL_VERSION: "60.0b13",
    //   FIREFOX_DEVEDITION: "60.0b13",
    //   LATEST_FIREFOX_OLDER_VERSION: "3.6.28",
    //   LATEST_FIREFOX_RELEASED_DEVEL_VERSION: "60.0b13",
    //   LATEST_FIREFOX_VERSION: "59.0.2" }
    const res = {};
    res.nightly = getMajor(pd.FIREFOX_NIGHTLY);
    res.esr = getMajor(pd.FIREFOX_ESR);
    res.beta = getMajor(pd.LATEST_FIREFOX_RELEASED_DEVEL_VERSION);
    res.release = getMajor(pd.LATEST_FIREFOX_VERSION);
    return res
  }

  function statusFlags(affected, productDetails) {
    if (affected !== null && productDetails !== null) {
      const affectedSelects = [];
      const wontfixSelects = []
      for (let chan in affected) {
        const majors = affected[chan];
        const v = productDetails[chan];
        if (majors.includes(v)) {
          const vs = v.toString();
          const flag = "cf_status_firefox" + (chan === "esr" ? ("_esr" + vs) : vs);
          const select = document.getElementById(flag);
          if (select !== null) {
            const val = select.options[select.selectedIndex].value;
            if (val === "---" || val === "unaffected") {
              affectedSelects.push(select);
            }
          }
        }
      }
      document.querySelectorAll("select[id^='cf_status_firefox']").forEach(select => {
        const val = select.options[select.selectedIndex].value;
        if (val === "affected" || val === "fix-optional" || val === "?") {
          const info = getMajorFromSF(select.id);
          if (info.esr) {
            if (info.version < productDetails.esr) {
              wontfixSelects.push(select);
            }
          } else if (info.version < productDetails.release) {
            wontfixSelects.push(select);
          }
        }
      });

      if (affectedSelects.length == 0 && wontfixSelects.length == 0) {
        return null;
      }
      return {affected: affectedSelects,
              wontfix: wontfixSelects}
    }
    return null;
  }

  function addUpdateSFButton(statusFlagsSelects) {
    if (statusFlagsSelects !== null) {
      const e = document.getElementById("crash-stop-usf-button");
      e.setAttribute("style", "display:block;position:relative;");
    }
  }

  let oldWay = false;
  let container = document.getElementById("module-details-content");
  if (!container) {
    container = document.getElementById("field_label_cf_crash_signature");
    oldWay = true;
  }

  if (container) {
    const signatures = [];
    const selector = oldWay ? "cf_crash_signature_edit_container" : "field-value-cf_crash_signature";
    const baseCrashUrl = "https://crash-stats.mozilla.com/signature/?signature=";
    document.querySelectorAll("#" + selector + " a").forEach(a => {
      if (a.href.startsWith(baseCrashUrl)) {
        const encodedSignature = a.href.replace(baseCrashUrl, "")
        signatures.push("s=" + encodedSignature);
      }
    });
    if (signatures.length != 0) {
      let productDetails = null;
      fetchProductDetails().then(data => {
        productDetails = getMajors(data);
      });

      const extraSocorroArgs = []
      const baseUrl = "https://crash-stats.mozilla.com/search/";
      const sayNo = new Set(["_columns", "_facets", "_facets_size", "_sort", "_results_number", "date", "channel", "product", "version", "build_id"]);
      const urlSelector = oldWay ? "bz_url_edit_container" : "field-value-bug_file_loc";
      document.querySelectorAll("#" + urlSelector + " a").forEach(a => {
        if (a.href.startsWith(baseUrl)) {
          const params = new URLSearchParams(a.href.slice(baseUrl.length));
          for (let p of params) {
            if (!sayNo.has(p[0])) {
              extraSocorroArgs.push(p[0] + "=" + encodeURIComponent(p[1]));
            }
          }
        }
      });
      const hgurlPattern = new RegExp("^http[s]?://hg\\.mozilla\\.org/(?:releases/)?mozilla-([^/]*)/rev/([0-9a-f]+)$");
      const esrPattern = new RegExp("^esr[0-9]+$");
      const repos = new Set(["central", "beta", "release"]);
      const hgrevs = [];
      let isFirst = false;
      let currentCommentId = "";
      const aSelector = oldWay ? ".bz_comment_text > a" : ".comment-text > a";
      document.querySelectorAll(aSelector).forEach(a => {
        const parentId = a.parentNode.attributes.id;
        let hasBugherderKw = false;
        let hasUpliftKw = false;
        if (parentId !== currentCommentId) {
          // we're in a new comment
          currentCommentId = parentId;
          isFirst = false;
          // here we check that we've bugherder or uplift keyword
          let commentTagSelector = "";
          let x = "";
          if (oldWay) {
            const parts = parentId.value.split("_");
            if (parts.length == 3) {
              const num = parts[2];
              const ctag = "comment_tag_" + num;
              commentTagSelector = "#" + ctag + " .bz_comment_tag";
              x = "x" + String.fromCharCode(160); // &nbsp;
            }
          } else {
            const parts = parentId.value.split("-");
            if (parts.length == 2) {
              const num = parts[1];
              const ctag = "ctag-" + num;
              commentTagSelector = "#" + ctag + ">.comment-tags>.comment-tag";
              x = "x";
            }
          }
          if (commentTagSelector) {
            const xb = x + "bugherder";
            const xu = x + "uplift";
            document.querySelectorAll(commentTagSelector).forEach(span => {
              const text = span.innerText;
              if (!hasBugherderKw) {
                hasBugherderKw = text === xb;
              }
              if (!hasUpliftKw) {
                hasUpliftKw = text === xu;
              }
            });
          }
        }
        const prev = a.previousSibling;
        if (prev == null || (prev.previousSibling == null && !prev.textContent.trim())) {
          // the first element in the comment is the link (no text before)
          isFirst = true;
        }
        if (isFirst || hasBugherderKw || hasUpliftKw) {
          // so we take the first link and the following ones only if they match the pattern
          const link = a.href;
          const m = link.match(hgurlPattern);
          if (m != null) {
            let repo = m[1];
            if (repos.has(repo) || repo.match(esrPattern)) {
              if (repo === "central") {
                repo = "nightly";
              }
              let rev = m[2];
              if (rev.length > 12) {
                rev = rev.slice(0, 12);
              }
              hgrevs.push("h=" + repo + "%7C" /* | */ + rev);
            }
          }
        }
      });

      // const crashStop = "https://localhost:8001";
      const crashStop = "https://crash-stop-addon.herokuapp.com";
      const sumup = crashStop + "/sumup.html";
      const hpart = hgrevs.length != 0 ? (hgrevs.join("&") + "&") : "";
      const spart = signatures.join("&") + "&";
      const extra = extraSocorroArgs.join("&");
      const vpart = "v=" + VERSION + "&";
      const crashStopLink = sumup + "?" + vpart + hpart + spart + extra;
      const LSName = "Crash-Stop-V1";
      const iframe = document.createElement("iframe");
      let statusFlagsSelects = null;
      let bugid = "";
      const meta = document.querySelector("meta[property='og:url']");
      const content = meta.getAttribute("content");
      const start = "https://bugzilla.mozilla.org/show_bug.cgi?id=";
      if (content.startsWith(start)) {
        bugid = content.slice(start.length);
        if (isNaN(bugid)) {
          bugid = "";
        }
      }
      window.addEventListener("message", function (e) {
        if (e.origin == crashStop) {
          const iframe = document.getElementById("crash-stop-iframe");
          iframe.style.height = e.data.height + "px";
          statusFlagsSelects = statusFlags(e.data.affected, productDetails);
          addUpdateSFButton(statusFlagsSelects);
        }
      });
      iframe.setAttribute("src", crashStopLink);
      iframe.setAttribute("id", "crash-stop-iframe");
      iframe.setAttribute("tabindex", "0");
      iframe.setAttribute("style", "display:block;width:100%;height:100%;border:0px;");
      const titleDiv = document.createElement("div");
      titleDiv.setAttribute("title", "Hide crash-stop");
      titleDiv.setAttribute("style", "display:inline;cursor:pointer;color:black;font-size:13px");
      const spinner = document.createElement("span");
      spinner.setAttribute("role", "button");
      spinner.setAttribute("tabindex", "0");
      spinner.setAttribute("style", "padding-right:5px;cursor:pointer;color:#999;");

      function hide() {
        spinner.innerText = "▸";
        spinner.setAttribute("aria-expanded", "false");
        spinner.setAttribute("aria-label", "show crash-stop");
        titleDiv.innerText = "Show table";
      };
      function show() {
        spinner.innerText = "▾";
        spinner.setAttribute("aria-expanded", "true");
        spinner.setAttribute("aria-label", "hide crash-stop");
        titleDiv.innerText = "Hide table";
      };
      function getLSData(id) {
        const s = localStorage.getItem(LSName);
        if (typeof id === "undefined") { // Function has no arguments
          return s === null ? new Object() : JSON.parse(s);
        } else {
          return s !== null && s !== "" && JSON.parse(s).hasOwnProperty(id);
        }
      }
      function setLSData(id) {
        if (id !== "") {
          const o = getLSData();
          o[id] = 1;
          localStorage.setItem(LSName, JSON.stringify(o));
        }
      }
      function unsetLSData(id) {
        if (id !== "") {
          const o = getLSData();
          if (o.hasOwnProperty(id)) {
            delete o[id];
            localStorage.setItem(LSName, JSON.stringify(o));
          }
        }
      }
      function toggle() {
        if (spinner.getAttribute("aria-expanded") === "true") {
          iframe.style.display = 'none';
          hide();
          setLSData(bugid);
        } else {
          if (!rightDiv.contains(iframe)) {
            rightDiv.append(iframe);
          }
          iframe.style.display = 'block';
          show();
          unsetLSData(bugid);
        }
      };
      function toggleOnKey(e) {
        if (e.keyCode == 13 || e.keyCode == 32) {
          toggle();
        }
      };

      spinner.addEventListener("click", toggle, false);
      spinner.addEventListener("keydown", toggleOnKey, false);
      titleDiv.addEventListener("click", toggle, false);
      titleDiv.addEventListener("keydown", toggleOnKey, false);
      const spanSpinner = document.createElement("span");
      spanSpinner.append(spinner, titleDiv);
      const rightDiv = document.createElement("div");
      rightDiv.setAttribute("class", "value");
      rightDiv.append(spanSpinner);

      const divButton = document.createElement("div");
      const button = document.createElement("button");
      divButton.setAttribute("id", "crash-stop-usf-button");
      divButton.setAttribute("style", "display:none;");
      button.setAttribute("type", "button");
      button.setAttribute("style", "position:absolute;right:0;bottom:2px");
      button.innerText = "Update status flags";
      button.addEventListener("click", updateStatusFlags, false);
      divButton.append(button);
      rightDiv.append(divButton);

      //localStorage.removeItem(LSName);
      if (getLSData(bugid)) {
        hide();
      } else {
        rightDiv.append(iframe);
        show();
      }

      // Update Status Flags button
      function updateStatusFlags() {
        if (statusFlagsSelects !== null) {
          if (oldWay) {
            // <a href="#" name="tracking" class="edit_tracking_flags_link">edit</a>
            document.querySelectorAll("a.edit_tracking_flags_link[name='tracking']").forEach(a => {
              a.click();
            });
          } else {
            document.getElementById("mode-btn").click();
            const e = document.getElementById("module-firefox-tracking-flags");
            e.scrollIntoView();
          }
          statusFlagsSelects.affected.map(function (select) {
            select.value = "affected";
            select.style = "color:red;";
          });
          statusFlagsSelects.wontfix.map(function (select) {
            select.value = "wontfix";
            select.style = "color:red;";
          });
        }
      }

      if (oldWay) {
        const tr = document.createElement("tr");
        const th = document.createElement("th");
        th.setAttribute("class", "field_label");
        tr.append(th);
        const a = document.createElement("a");
        a.setAttribute("class", "field_help_link");
        a.setAttribute("title", "Crash data from Bugzilla Crash Stop addon");
        a.setAttribute("href", "https://addons.mozilla.org/firefox/addon/bugzilla-crash-stop/");
        a.innerText = "Crash data:";
        th.append(a);
        const td = document.createElement("td");
        td.setAttribute("class", "field_value");
        td.setAttribute("colspan", 2);
        td.append(rightDiv);
        tr.append(td);
        container = container.parentNode;
        container.parentNode.insertBefore(tr, container.nextSibling);
      } else {
        const mainDiv = document.createElement("div");
        mainDiv.setAttribute("class", "field");
        const leftDiv = document.createElement("div");
        leftDiv.setAttribute("class", "name");
        leftDiv.innerText = "Crash Data:";
        mainDiv.append(leftDiv, rightDiv);
        container.append(mainDiv);
      }
    }
  }
}, { once: true });
