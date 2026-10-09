/* ===========================================================================
   客户端分页器
   站点没有服务端分页（?page= / ?per_page= / ?limit= / ?offset= 全部无效），
   所以只能把已下载的卡片列表在本地切片。

   代码里的 PER 占位符会在注入前被替换成「每页帖子数」，0 表示全部（即不启用分页）。
   该占位符全文件只出现一次（下方 var PER = ... 那一行），这样 Java 的
   String.replace（替换全部）与 JS 的 replace（只替换首个）行为一致，工具链不会踩坑。

   这个文件是唯一事实来源：App 读它注入，离线预览与单元测试也读它做验证。
   =========================================================================== */
(function () {
  function storageGet(k) { try { return sessionStorage.getItem(k); } catch (e) { return null; } }
  function storageSet(k, v) { try { sessionStorage.setItem(k, String(v)); } catch (e) {} }

  try {
    var PER = __PER__;
    var d = document;
    var SEL = 'article.card.post, .favorites-list > .card, .favorites-list > article,'
            + ' .favorites-list > .favorite-card';
    var items = [].slice.call(d.querySelectorAll(SEL));
    var old = d.getElementById('fx-pager');

    // 先恢复所有卡片，避免上一页的隐藏状态残留（例如切回「全部」时）
    for (var i = 0; i < items.length; i++) { items[i].style.display = ''; }

    function drop() { if (old && old.parentNode) { old.parentNode.removeChild(old); } }
    if (items.length === 0 || PER <= 0) { drop(); return; }

    var total = items.length;
    var pages = Math.ceil(total / PER);
    if (pages <= 1) { drop(); return; }   // 只有一页就不显示分页器

    var host = items[items.length - 1].parentNode;
    var key = 'fxPage:' + location.pathname + location.search;
    var cur = parseInt(storageGet(key) || '1', 10);
    if (!(cur >= 1)) { cur = 1; }
    if (cur > pages) { cur = pages; }

    var wrap = old;
    if (!wrap) {
      wrap = d.createElement('div');
      wrap.id = 'fx-pager';
      wrap.className = 'fx-pager';
    }

    function mk(label, page, dis, active, ell) {
      if (ell) {
        var sp = d.createElement('span');
        sp.className = 'fx-ellipsis';
        sp.textContent = '…';
        wrap.appendChild(sp);
        return;
      }
      var b = d.createElement('button');
      b.type = 'button';
      b.textContent = label;
      b.className = 'fx-page' + (active ? ' fx-current' : '');
      if (dis) { b.disabled = true; } else { b.addEventListener('click', function () { go(page); }); }
      wrap.appendChild(b);
    }

    function draw() {
      var s = (cur - 1) * PER;
      var e = Math.min(s + PER, total);
      for (var i = 0; i < items.length; i++) {
        items[i].style.display = (i >= s && i < e) ? '' : 'none';
      }
      wrap.innerHTML = '';

      mk('上一页', cur - 1, cur <= 1, false, false);

      var list = [];
      if (pages <= 7) {
        for (var q = 1; q <= pages; q++) { list.push(q); }
      } else {
        list.push(1);
        var a = Math.max(2, cur - 2);
        var z = Math.min(pages - 1, cur + 2);
        if (a > 2) { list.push(-1); }
        for (var q2 = a; q2 <= z; q2++) { list.push(q2); }
        if (z < pages - 1) { list.push(-1); }
        list.push(pages);
      }
      for (var k = 0; k < list.length; k++) {
        var p = list[k];
        if (p === -1) { mk('', 0, false, false, true); }
        else { mk(String(p), p, false, p === cur, false); }
      }

      mk('下一页', cur + 1, cur >= pages, false, false);

      var info = d.createElement('div');
      info.className = 'fx-info';
      info.textContent = '第 ' + cur + ' / ' + pages + ' 页 · 共 ' + total + ' 条';
      wrap.appendChild(info);
    }

    function go(p) {
      if (p < 1 || p > pages || p === cur) { return; }
      cur = p;
      storageSet(key, cur);
      draw();
      try { window.scrollTo(0, 0); } catch (e) {}
    }

    var anchor = items[items.length - 1];
    if (anchor.nextSibling) { host.insertBefore(wrap, anchor.nextSibling); }
    else { host.appendChild(wrap); }
    draw();
  } catch (e) { /* 分页失败绝不影响页面本身 */ }
})();
