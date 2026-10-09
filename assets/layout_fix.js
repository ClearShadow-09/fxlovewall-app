/* ===========================================================================
   动作区布局修正 + 图标化。

   做两件事：

   1) 把「举报」（自己的帖子则是「删除自己的帖子」）搬到「展开全文」那一行的
      最右侧。站点结构（article.card.post 的直接子元素顺序）：
        .post-meta → .tags → .post-content → .post-fold-toggle → .post-actions
      「举报」原本在 .post-actions 里，与点赞/分享/收藏/评论同一行。纯 CSS 无法
      跨父级移动元素（order 只在同一父级的兄弟间生效），所以这里用 JS 把它
      （连同它所在的 form）真的搬过去，并包一层 .fx-tail flex 行：

        长帖：[展开全文] ................ [举报 / 删除]
        短帖：[举报 / 删除]               （展开全文被 hidden，右侧仍靠最右）

      ⚠️ 为什么不按 class 找举报：站点的举报按钮到底是 .text-danger-button 还是
      button.danger（站点 CSS 里两个都存在）无法从已登录页面之外确认，一旦猜错，
      就会同时出现「没被搬走」和「仍然是胶囊」两个症状。所以这里改成
      **按文字「举报」查找**，再打上自己的 .fx-report 标记类，由 App 的 CSS 负责
      外观，从此不依赖站点的任何类名。
      「删除自己的帖子」反过来 —— 它只在登录后出现，而 .right-actions 里的
      .text-danger-button 语义明确，所以先按类找、再按文字「删除」兜底。

   2) 给动作控件打上 .fx-ico 图标标记（见 theme.css「动作区：图标 + 文字」一节）：
        【图标+点赞数】【图标+(已)收藏】【图标+分享】【图标+评论】
      间距复用 mask + currentColor，空心/实心只换 --fx-ico-on，颜色自动跟随。

   注意：是「移动节点」而不是「重建节点」，所以站点自己绑的事件监听、以及折叠
   按钮的 hidden 切换逻辑都不会失效。
   =========================================================================== */
(function () {
  function textOf(el) {
    var t = el.textContent || '';
    if (!t && el.value) { t = el.value; }
    return t.replace(/\s+/g, '');
  }

  /** 帖子自己的动作行。刻意限定在 .post-actions 里，免得抓到评论区的删除。 */
  function ownActions(card) {
    return card.querySelector('.post-actions .right-actions')
        || card.querySelector('.post-actions-v4 .right-actions')
        || card.querySelector('.post-actions .left-actions')
        || null;
  }

  /** 在卡片内按文字找举报控件；优先完全等于「举报」，否则退而求其次用包含匹配。 */
  function findReport(card) {
    var scope = ownActions(card) || card;
    var nodes = scope.querySelectorAll('button, a, input');
    var loose = null;
    for (var i = 0; i < nodes.length; i++) {
      var t = textOf(nodes[i]);
      if (t === '举报') { return nodes[i]; }
      if (!loose && t.indexOf('举报') >= 0) { loose = nodes[i]; }
    }
    return loose;
  }

  /** 「删除自己的帖子」。自己的帖子没有举报，位置和样式与举报完全一致。 */
  function findDelete(card) {
    var scope = card.querySelector('.post-actions .right-actions')
             || card.querySelector('.post-actions-v4 .right-actions');
    if (!scope) { return null; }
    var byClass = scope.querySelector('.text-danger-button, button.danger');
    if (byClass && textOf(byClass).indexOf('举报') < 0) { return byClass; }
    var nodes = scope.querySelectorAll('button, a');
    for (var i = 0; i < nodes.length; i++) {
      if (textOf(nodes[i]).indexOf('删除') >= 0) { return nodes[i]; }
    }
    return null;
  }

  // ---------------------------------------------------------------- 图标化

  /** 点赞 / 收藏的「已开启」判据。站点用什么类名无法离线确认，所以三种都认。 */
  function isOn(el) {
    return el.classList.contains('liked')
        || el.classList.contains('is-liked')
        || el.classList.contains('favorited')
        || el.classList.contains('active')
        || el.getAttribute('aria-pressed') === 'true';
  }

  function iconify(el, kind) {
    if (!el || el.nodeType !== 1) { return; }
    el.classList.add('fx-ico');
    el.style.setProperty('--fx-ico', 'var(--fx-ico-' + kind + ')');
    if (kind === 'like' || kind === 'star') {
      el.style.setProperty('--fx-ico-on', 'var(--fx-ico-' + kind + '-on)');
    }

    // 已开启态每次都要重新对一遍：站点点赞/收藏是 AJAX 切 class 的，
    // 而这个脚本会重复跑（run() 在 300ms / 1200ms 各补一次）。
    // 早先这里用「已经有 .fx-ico 就 return」做幂等，结果第一次渲染成空心之后，
    // 用户点了赞也永远不会变成实心 —— 惰性初始化在这里是错的，状态要同步。
    el.classList.toggle('fx-on', isOn(el));

    // 点赞：需求是【图标+点赞数】。站点渲染成「点赞 7」——两个字和数字在同一个
    // 文本节点里，CSS 拆不开，所以这里把数字抠出来放进 data-fx-count，
    // 再由 .fx-num + attr() 把它画回去。数字每次都要重取（点赞数会变）。
    if (kind === 'like') {
      var m = textOf(el).match(/\d+/);
      if (m) {
        el.setAttribute('data-fx-count', m[0]);
        el.classList.add('fx-num');
      }
    }
  }

  /**
   * 点赞控件。
   *
   * ⚠️ 这是踩过的坑：站点的点赞**不在** .right-actions 里，而是在
   * .left-actions 里（`<div class="left-actions"><span class="muted">点赞 7</span></div>`）。
   * 早先只在 .right-actions 里找 .like-button，登录与否都找不到，所以点赞永远没图标。
   * 现在的顺序：
   *   1) .left-actions 里的 .like-button（登录后站点给的真按钮）
   *   2) 卡片里任意位置的 .like-button
   *   3) .left-actions 里文字含「点赞」的那个节点（未登录时的 <span class="muted">）
   */
  function findLike(card) {
    var la = card.querySelector('.left-actions');
    var byClass = (la && la.querySelector('.like-button')) || card.querySelector('.like-button');
    if (byClass) { return byClass; }
    var scopes = la ? [la, card] : [card];
    for (var s = 0; s < scopes.length; s++) {
      var nodes = scopes[s].querySelectorAll('span, button, a');
      for (var i = 0; i < nodes.length; i++) {
        if (textOf(nodes[i]).indexOf('点赞') >= 0) { return nodes[i]; }
      }
    }
    return null;
  }

  function iconifyCard(card) {
    var ra = card.querySelector('.post-actions .right-actions')
          || card.querySelector('.post-actions-v4 .right-actions')
          || card.querySelector('.right-actions');

    // 点赞：左右两边都找（见 findLike 的说明）
    iconify(findLike(card), 'like');

    if (ra) {
      iconify(ra.querySelector('.favorite-button'), 'star');
      iconify(ra.querySelector('.share-button'), 'share');
      // 「评论 N」是 .right-actions 的直接子级 <a>。排除举报/删除，它们不是动作图标。
      var links = ra.querySelectorAll('a[href]');
      for (var i = 0; i < links.length; i++) {
        var a = links[i];
        if (a.classList.contains('fx-report') || a.classList.contains('fx-delete')) { continue; }
        if (a.classList.contains('text-danger-button') || a.classList.contains('like-button')
            || a.classList.contains('favorite-button') || a.classList.contains('share-button')) { continue; }
        if (a.querySelector('button')) { continue; }
        iconify(a, 'comment');
      }
    }
  }

  // ---------------------------------------------------------------- 卡片底色
  /**
   * 把主题色淡底**内联**写到卡片上。
   *
   * 为什么不只靠 theme.css 里的 `.card { background-color: var(--fx-card-bg) }`：
   * 那条规则确实在（探针确认：注入表里有、选择器能匹配、变量值正确、
   * `!important` 也在），但在这台 WebView 上就是不生效 —— 卡片的最终底色
   * 始终是站点自己的 `white`。而**同样的声明内联到元素上就立即生效**
   * （实测像素 rgb(218,226,254)，正是 rgba(49,94,251,.18) 叠白的结果）。
   *
   * 与其继续和这个解析差异纠缠，不如改成已验证可行的方式：注入后由这段 JS
   * 把从 CSS 变量读到的颜色直接写到每张卡片上。主题色/明暗变化时
   * injectAll 会重跑，这里跟着重算，所以换色依然实时。
   */
  function paintCards() {
    try {
      var cs = getComputedStyle(document.documentElement);
      var bg = cs.getPropertyValue('--fx-card-bg').trim();
      var inputBg = cs.getPropertyValue('--fx-input-bg').trim();
      if (!bg) { return; }
      var cards = document.querySelectorAll(
        '.card, .favorite-card, .comment, .comment-form');
      for (var i = 0; i < cards.length; i++) {
        cards[i].style.setProperty('background-color', bg, 'important');
      }
      var forms = document.querySelectorAll('.form-card, .post-editor');
      for (var j = 0; j < forms.length; j++) {
        if (inputBg) {
          forms[j].style.setProperty('background-color', inputBg, 'important');
        }
      }
    } catch (e) { /* 上色失败绝不影响页面本身 */ }
  }

  // ---------------------------------------------------------------- 搬移

  function fixCard(card) {
    var node = null;
    var cls = null;

    var del = findDelete(card);
    if (del) {
      node = del;
      cls = 'fx-delete';
    } else {
      var rep = findReport(card);
      if (rep) {
        node = rep;
        cls = 'fx-report';
      }
    }

    // 标记类先打上，外观（中性灰纯文字）由 App 的 CSS 决定
    if (node) { node.classList.add(cls); }

    // 整只 form 一起搬最稳妥；但 form 里若还夹着别的动作控件，就只搬按钮本身
    var form = node && node.closest ? node.closest('form') : null;
    var crowded = form && form.querySelector(
      '.like-button, .favorite-button, .share-button, .post-fold-toggle,'
      + ' .fx-report:not(:first-child), .fx-delete:not(:first-child)');
    var move = (form && !crowded) ? form : node;

    var toggle = card.querySelector('.post-fold-toggle');
    var tail = card.querySelector('.fx-tail');

    // 没有举报/删除：如果之前建过 .fx-tail 而里面只剩展开全文，把它拆掉还原
    if (!move) {
      if (tail && toggle && tail.children.length <= 1) {
        tail.parentNode.insertBefore(toggle, tail);
        tail.parentNode.removeChild(tail);
      }
      return;
    }

    if (!tail) {
      tail = document.createElement('div');
      tail.className = 'fx-tail';
      // 优先占据「展开全文」原来的位置；短帖则插在动作行之前
      var ref = toggle || card.querySelector('.post-actions');
      if (ref && ref.parentNode) { ref.parentNode.insertBefore(tail, ref); }
      else { card.appendChild(tail); }
    }
    if (toggle && toggle.parentNode !== tail) { tail.appendChild(toggle); }
    if (move.parentNode !== tail) { tail.appendChild(move); }
  }

  function run() {
    try {
      paintCards();
      var cards = document.querySelectorAll('article.card.post, .favorite-card');
      for (var i = 0; i < cards.length; i++) {
        fixCard(cards[i]);
        iconifyCard(cards[i]);
      }
    } catch (e) {
      // 布局修正失败绝不能影响页面本身。但也不能完全哑掉 —— 0.7.x 时这里
      // 吞过一次异常，表现成「图标/搬迁全都不生效」，排查花了两轮。
      try { if (window.console) { console.warn('[fxwall] layout_fix failed:', e); } } catch (_) {}
    }
  }

  run();
  // 动作区也有可能是站点脚本在 load 之后才渲染的，补两次。
  // run() 是幂等的（重复执行不会重复搬或生成第二个 .fx-tail）。
  setTimeout(run, 300);
  setTimeout(run, 1200);
})();
