$ErrorActionPreference = "Stop"

$outputRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentRoot = Split-Path -Parent $outputRoot
$sourceRoot = Get-ChildItem -LiteralPath $parentRoot -Directory |
  Where-Object { $_.Name -like "*07" } |
  Select-Object -First 1 -ExpandProperty FullName

if (-not (Test-Path -LiteralPath $sourceRoot)) {
  throw "Nao foi possivel localizar a pasta de origem: $sourceRoot"
}

$views = @(
  @{ Name = "login"; Html = "login.html"; Js = "login.js"; Css = "login.css"; Title = "Login - Controle de Licitacao" },
  @{ Name = "alterar-senha"; Html = "alterar-senha.html"; Js = "alterar-senha.js"; Css = "login.css"; Title = "Alterar Senha - Controle de Licitacao" },
  @{ Name = "admin"; Html = "admin.html"; Js = "admin.js"; Css = "admin.css"; Title = "Administracao - Controle de Licitacao" },
  @{ Name = "divacp"; Html = "divacp.html"; Js = "divacp.js"; Css = "divacp.css"; Title = "Controle de Licitacao - DIVACP" },
  @{ Name = "divcon"; Html = "divcon.html"; Js = "divcon.js"; Css = "divcon.css"; Title = "Controle de Licitacao - DIVCON" },
  @{ Name = "cpc"; Html = "cpc.html"; Js = "cpc.js"; Css = "cpc.css"; Title = "Controle de Licitacao - CPC" },
  @{ Name = "cec"; Html = "cec.html"; Js = "cec.js"; Css = "cec.css"; Title = "Controle de Licitacao - CEC" },
  @{ Name = "dipreg"; Html = "dipreg.html"; Js = "dipreg.js"; Css = "dipreg.css"; Title = "Controle de Licitacao - DIPREG" }
)

$legacyPages = @{
  "login.html" = "login"
  "alterar-senha.html" = "alterar-senha"
  "admin.html" = "admin"
  "divacp.html" = "divacp"
  "divcon.html" = "divcon"
  "cpc.html" = "cpc"
  "cec.html" = "cec"
  "dipreg.html" = "dipreg"
}

function Get-BodyContent {
  param([string]$Path)

  $raw = Get-Content -LiteralPath (Join-Path $sourceRoot $Path) -Raw
  $match = [regex]::Match($raw, "<body[^>]*>([\s\S]*?)</body>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if (-not $match.Success) {
    throw "Nao foi possivel localizar o <body> em $Path"
  }

  $body = $match.Groups[1].Value
  $body = [regex]::Replace(
    $body,
    "<script\b[^<]*(?:(?!</script>)<[^<]*)*</script>",
    "",
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
  )

  return $body.Trim()
}

function Get-ScopedCssBlock {
  param(
    [string]$Route,
    [string]$CssPath
  )

  $css = Get-Content -LiteralPath (Join-Path $sourceRoot $CssPath) -Raw
  $css = [regex]::Replace($css, "(?m)^:root\s*\{", ":scope {")
  $css = [regex]::Replace($css, "(?m)^body\s*\{", ":scope {")

  return @"
/* $Route */
@scope (body.route-$Route) {
$css
}
"@
}

$templateMap = @{}
$scriptMap = @{}
$titleMap = @{}
$cssBlocks = New-Object System.Collections.Generic.List[string]

foreach ($view in $views) {
  $templateMap[$view.Name] = "tpl-$($view.Name)"
  $scriptMap[$view.Name] = [string](Get-Content -LiteralPath (Join-Path $sourceRoot $view.Js) -Raw)
  $titleMap[$view.Name] = $view.Title
  $cssBlocks.Add((Get-ScopedCssBlock -Route $view.Name -CssPath $view.Css))
}

$templateHtml = ($views | ForEach-Object {
  $name = $_.Name
  $body = Get-BodyContent $_.Html
  @"
  <template id="tpl-$name">
$body
  </template>
"@
}) -join "`r`n`r`n"

$indexHtml = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Controle de Licitacao</title>
  <link rel="stylesheet" href="app.css" />
</head>
<body class="route-boot">
  <div id="app" class="app-shell"></div>

$templateHtml

  <script src="app.js"></script>
</body>
</html>
"@

$baseCss = @"
html,
body {
  min-height: 100%;
}

body {
  margin: 0;
}

.app-shell {
  min-height: 100vh;
}

template {
  display: none !important;
}

$($cssBlocks -join "`r`n`r`n")
"@

$templatesJson = $templateMap | ConvertTo-Json -Compress
$scriptsJson = $scriptMap | ConvertTo-Json -Compress -Depth 5
$titlesJson = $titleMap | ConvertTo-Json -Compress
$legacyJson = $legacyPages | ConvertTo-Json -Compress

$appJs = @"
(function () {
  const APP_TEMPLATE_IDS = $templatesJson;
  const APP_PAGE_SCRIPTS = $scriptsJson;
  const APP_PAGE_TITLES = $titlesJson;
  const APP_LEGACY_PAGES = $legacyJson;
  const APP_ROUTES = ["login", "alterar-senha", "admin", "divacp", "divcon", "cpc", "cec", "dipreg"];
  const DEFAULT_ROUTE = "login";

  function normalizeRoute(route) {
    const value = String(route || "").trim().toLowerCase();
    if (!value) return DEFAULT_ROUTE;
    if (value.endsWith(".html")) {
      return APP_LEGACY_PAGES[value] || DEFAULT_ROUTE;
    }
    return APP_ROUTES.includes(value) ? value : DEFAULT_ROUTE;
  }

  function getCurrentPageName() {
    return window.location.pathname.split(/[\\\\/]/).pop().toLowerCase();
  }

  function getCurrentRoute() {
    const hash = String(window.location.hash || "").replace(/^#\/?/, "");
    if (hash) return normalizeRoute(hash);
    const pageName = getCurrentPageName();
    if (pageName && APP_LEGACY_PAGES[pageName]) {
      return normalizeRoute(APP_LEGACY_PAGES[pageName]);
    }
    return DEFAULT_ROUTE;
  }

  function getUrlForRoute(route) {
    return "index.html#" + normalizeRoute(route);
  }

  function redirectToRoute(route, replace) {
    const destino = getUrlForRoute(route);
    if (replace) {
      window.location.replace(destino);
      return;
    }
    window.location.href = destino;
  }

  window.AppRouter = {
    getCurrentRoute,
    go(route, replace = false) {
      redirectToRoute(route, replace);
    },
    getUrl(route) {
      return getUrlForRoute(route);
    }
  };

  const AUTH_USERS_KEY = "licitacao_usuarios_v1";
  const AUTH_REQUESTS_KEY = "licitacao_solicitacoes_v1";
  const AUTH_SESSION_KEY = "licitacao_sessao_v1";

  const AUTH_ROUTE_BY_SECTOR = {
    ADMIN: "admin",
    DIVACP: "divacp",
    DIVCON: "divcon",
    CPC: "cpc",
    CEC: "cec",
    DIPREG: "dipreg"
  };

  function authNormalizeEmail(valor) {
    return String(valor || "").trim().toLowerCase();
  }

  function authNormalizeText(valor) {
    return String(valor || "").trim().toUpperCase();
  }

  function authReadJson(chave, fallback) {
    try {
      const valor = localStorage.getItem(chave);
      if (!valor) return fallback;
      return JSON.parse(valor);
    } catch (erro) {
      return fallback;
    }
  }

  function authWriteJson(chave, valor) {
    localStorage.setItem(chave, JSON.stringify(valor));
  }

  function authGenerateId(prefixo) {
    return prefixo + "_" + Date.now() + "_" + Math.random().toString(16).slice(2, 8);
  }

  function authGenerateTemporaryPassword() {
    const numero = Math.floor(1000 + Math.random() * 9000);
    return "NOVA" + numero;
  }

  function authEnsureUserShape(usuario) {
    return {
      ...usuario,
      nome: authNormalizeText(usuario?.nome),
      email: authNormalizeEmail(usuario?.email),
      setor: authNormalizeText(usuario?.setor),
      perfil: authNormalizeText(usuario?.perfil || (authNormalizeText(usuario?.setor) === "ADMIN" ? "ADMIN" : "SETOR")),
      senha: String(usuario?.senha || "").trim(),
      ativo: usuario?.ativo !== false,
      precisaTrocarSenha: Boolean(usuario?.precisaTrocarSenha),
      senhaTemporaria: Boolean(usuario?.senhaTemporaria)
    };
  }

  function authSeedUsers() {
    const usuarios = authReadJson(AUTH_USERS_KEY, []).map(authEnsureUserShape);
    const temAdmin = usuarios.some((usuario) => authNormalizeEmail(usuario.email) === "admin@licitacao.local");

    if (!temAdmin) {
      usuarios.push({
        id: authGenerateId("user"),
        nome: "ADMINISTRADOR DO SISTEMA",
        email: "admin@licitacao.local",
        senha: "admin123",
        setor: "ADMIN",
        perfil: "ADMIN",
        ativo: true,
        precisaTrocarSenha: false,
        senhaTemporaria: false,
        criadoEm: new Date().toISOString()
      });
    }

    authWriteJson(AUTH_USERS_KEY, usuarios);
  }

  function authGetUsers() {
    authSeedUsers();
    return authReadJson(AUTH_USERS_KEY, []).map(authEnsureUserShape);
  }

  function authSaveUsers(usuarios) {
    authWriteJson(AUTH_USERS_KEY, usuarios.map(authEnsureUserShape));
  }

  function authGetRequests() {
    return authReadJson(AUTH_REQUESTS_KEY, []);
  }

  function authSaveRequests(solicitacoes) {
    authWriteJson(AUTH_REQUESTS_KEY, solicitacoes);
  }

  function authGetSession() {
    return authReadJson(AUTH_SESSION_KEY, null);
  }

  function authSetSession(sessao) {
    authWriteJson(AUTH_SESSION_KEY, sessao);
  }

  function authClearSession() {
    localStorage.removeItem(AUTH_SESSION_KEY);
  }

  function authGetRouteForSector(setor) {
    const route = AUTH_ROUTE_BY_SECTOR[authNormalizeText(setor)] || DEFAULT_ROUTE;
    return getUrlForRoute(route);
  }

  function authGetRedirectForSession(sessao) {
    if (!sessao) return getUrlForRoute("login");
    if (sessao.precisaTrocarSenha) return getUrlForRoute("alterar-senha");
    return authGetRouteForSector(sessao.perfil === "ADMIN" ? "ADMIN" : sessao.setor);
  }

  function authCreateAccessRequest(payload) {
    const nome = authNormalizeText(payload?.nome);
    const email = authNormalizeEmail(payload?.email);
    const setor = authNormalizeText(payload?.setor);

    if (!nome || !email || !setor) {
      return { ok: false, message: "Preencha nome completo, email e setor." };
    }

    const usuarios = authGetUsers();
    const usuarioExistente = usuarios.find((usuario) => authNormalizeEmail(usuario.email) === email);
    if (usuarioExistente && usuarioExistente.ativo) {
      return { ok: false, message: "Ja existe um cadastro ativo com esse email." };
    }

    const solicitacoes = authGetRequests();
    const pendencia = solicitacoes.find(
      (item) => authNormalizeEmail(item.email) === email && String(item.status || "").toUpperCase() === "PENDENTE"
    );

    if (pendencia) {
      return { ok: false, message: "Ja existe uma solicitacao pendente para esse email." };
    }

    solicitacoes.unshift({
      id: authGenerateId("request"),
      nome,
      email,
      setor,
      status: "PENDENTE",
      criadoEm: new Date().toISOString()
    });

    authSaveRequests(solicitacoes);
    return { ok: true };
  }

  function authLogin(email, senha, setorSelecionado) {
    const login = authNormalizeEmail(email);
    const senhaInformada = String(senha || "").trim();
    const setorInformado = authNormalizeText(setorSelecionado);
    const usuarios = authGetUsers();
    const usuario = usuarios.find((item) => authNormalizeEmail(item.email) === login);

    if (!usuario) {
      return { ok: false, message: "Cadastro nao encontrado. Solicite acesso." };
    }

    if (!usuario.ativo) {
      return { ok: false, message: "Seu acesso esta inativo. Fale com a administracao." };
    }

    if (!setorInformado) {
      return { ok: false, message: "Selecione o setor de acesso." };
    }

    const setorEsperado = usuario.perfil === "ADMIN" ? "ADMIN" : usuario.setor;
    if (setorInformado !== setorEsperado) {
      return { ok: false, message: "Este usuario nao possui acesso ao setor informado." };
    }

    if (String(usuario.senha || "").trim() !== senhaInformada) {
      return { ok: false, message: "Senha invalida." };
    }

    const sessao = {
      id: usuario.id,
      nome: usuario.nome,
      email: usuario.email,
      setor: usuario.setor,
      perfil: usuario.perfil,
      precisaTrocarSenha: Boolean(usuario.precisaTrocarSenha),
      entrouEm: new Date().toISOString()
    };

    authSetSession(sessao);
    return {
      ok: true,
      redirect: authGetRedirectForSession(sessao)
    };
  }

  function authLogout() {
    authClearSession();
    redirectToRoute("login", false);
  }

  function authApproveRequest(requestId) {
    const solicitacoes = authGetRequests();
    const indice = solicitacoes.findIndex((item) => item.id === requestId);
    if (indice === -1) {
      return { ok: false, message: "Solicitacao nao encontrada." };
    }

    const solicitacao = solicitacoes[indice];
    const usuarios = authGetUsers();
    const perfil = solicitacao.setor === "ADMIN" ? "ADMIN" : "SETOR";
    const senhaTemporaria = authGenerateTemporaryPassword();
    const usuarioExistente = usuarios.find((usuario) => authNormalizeEmail(usuario.email) === authNormalizeEmail(solicitacao.email));

    if (usuarioExistente) {
      usuarioExistente.nome = solicitacao.nome;
      usuarioExistente.setor = solicitacao.setor;
      usuarioExistente.perfil = perfil;
      usuarioExistente.senha = senhaTemporaria;
      usuarioExistente.ativo = true;
      usuarioExistente.precisaTrocarSenha = true;
      usuarioExistente.senhaTemporaria = true;
      usuarioExistente.atualizadoEm = new Date().toISOString();
    } else {
      usuarios.push({
        id: authGenerateId("user"),
        nome: solicitacao.nome,
        email: solicitacao.email,
        senha: senhaTemporaria,
        setor: solicitacao.setor,
        perfil,
        ativo: true,
        precisaTrocarSenha: true,
        senhaTemporaria: true,
        criadoEm: new Date().toISOString()
      });
    }

    solicitacoes[indice] = {
      ...solicitacao,
      status: "APROVADA",
      revisadoEm: new Date().toISOString()
    };

    authSaveUsers(usuarios);
    authSaveRequests(solicitacoes);
    return { ok: true, temporaryPassword: senhaTemporaria };
  }

  function authRejectRequest(requestId) {
    const solicitacoes = authGetRequests();
    const indice = solicitacoes.findIndex((item) => item.id === requestId);
    if (indice === -1) {
      return { ok: false, message: "Solicitacao nao encontrada." };
    }

    solicitacoes[indice] = {
      ...solicitacoes[indice],
      status: "NEGADA",
      revisadoEm: new Date().toISOString()
    };

    authSaveRequests(solicitacoes);
    return { ok: true };
  }

  function authResetUserPassword(userId) {
    const usuarios = authGetUsers();
    const usuario = usuarios.find((item) => item.id === userId);

    if (!usuario) {
      return { ok: false, message: "Usuario nao encontrado." };
    }

    const senhaTemporaria = authGenerateTemporaryPassword();
    usuario.senha = senhaTemporaria;
    usuario.precisaTrocarSenha = true;
    usuario.senhaTemporaria = true;
    usuario.atualizadoEm = new Date().toISOString();
    authSaveUsers(usuarios);
    return { ok: true, temporaryPassword: senhaTemporaria };
  }

  function authCompletePasswordChange(novaSenha) {
    const sessao = authGetSession();
    if (!sessao) {
      return { ok: false, message: "Sessao nao encontrada." };
    }

    const senha = String(novaSenha || "").trim();
    if (senha.length < 6) {
      return { ok: false, message: "A nova senha deve ter pelo menos 6 caracteres." };
    }

    const usuarios = authGetUsers();
    const usuario = usuarios.find((item) => item.id === sessao.id);
    if (!usuario) {
      return { ok: false, message: "Usuario nao encontrado." };
    }

    usuario.senha = senha;
    usuario.precisaTrocarSenha = false;
    usuario.senhaTemporaria = false;
    usuario.atualizadoEm = new Date().toISOString();
    authSaveUsers(usuarios);

    const novaSessao = {
      ...sessao,
      precisaTrocarSenha: false
    };

    authSetSession(novaSessao);
    return { ok: true, redirect: authGetRedirectForSession(novaSessao) };
  }

  function authToggleUserStatus(userId) {
    const usuarios = authGetUsers();
    const usuario = usuarios.find((item) => item.id === userId);

    if (!usuario) {
      return { ok: false, message: "Usuario nao encontrado." };
    }

    if (authNormalizeEmail(usuario.email) === "admin@licitacao.local" && usuario.ativo) {
      return { ok: false, message: "O administrador padrao nao pode ser inativado." };
    }

    usuario.ativo = !usuario.ativo;
    authSaveUsers(usuarios);
    return { ok: true, ativo: usuario.ativo };
  }

  function authUpdateUserSector(userId, setor) {
    const usuarios = authGetUsers();
    const usuario = usuarios.find((item) => item.id === userId);

    if (!usuario) {
      return { ok: false, message: "Usuario nao encontrado." };
    }

    usuario.setor = authNormalizeText(setor);
    usuario.perfil = usuario.setor === "ADMIN" ? "ADMIN" : "SETOR";
    authSaveUsers(usuarios);
    return { ok: true };
  }

  function authHydratePage() {
    const sessao = authGetSession();
    if (!sessao) return;

    const campoNome = document.querySelector("[data-auth-nome]");
    const campoSetor = document.querySelector("[data-auth-setor]");

    if (campoNome) campoNome.textContent = sessao.nome;
    if (campoSetor) campoSetor.textContent = sessao.setor;
  }

  function authProtectRoute(route) {
    const sessao = authGetSession();

    if (route === "login") {
      if (sessao) {
        const destino = normalizeRoute(authGetRedirectForSession(sessao).split("#").pop());
        if (destino !== route) {
          redirectToRoute(destino, true);
          return null;
        }
      }
      return route;
    }

    if (route === "alterar-senha") {
      if (!sessao) {
        redirectToRoute("login", true);
        return null;
      }

      if (!sessao.precisaTrocarSenha) {
        const destino = normalizeRoute(authGetRedirectForSession(sessao).split("#").pop());
        if (destino !== route) {
          redirectToRoute(destino, true);
          return null;
        }
      }
      return route;
    }

    if (!sessao) {
      redirectToRoute("login", true);
      return null;
    }

    if (sessao.precisaTrocarSenha) {
      redirectToRoute("alterar-senha", true);
      return null;
    }

    if (route === "admin") {
      if (sessao.perfil !== "ADMIN") {
        const destino = normalizeRoute(authGetRouteForSector(sessao.setor).split("#").pop());
        redirectToRoute(destino, true);
        return null;
      }
      return route;
    }

    const setorEsperado = authNormalizeText(sessao.setor);
    const routeEsperada = normalizeRoute(AUTH_ROUTE_BY_SECTOR[setorEsperado] || "login");
    if (sessao.perfil !== "ADMIN" && route !== routeEsperada) {
      redirectToRoute(routeEsperada, true);
      return null;
    }

    return route;
  }

  window.AuthSistema = {
    getUsers: authGetUsers,
    getRequests: authGetRequests,
    getSession: authGetSession,
    login: authLogin,
    logout: authLogout,
    createAccessRequest: authCreateAccessRequest,
    approveRequest: authApproveRequest,
    rejectRequest: authRejectRequest,
    resetUserPassword: authResetUserPassword,
    completePasswordChange: authCompletePasswordChange,
    toggleUserStatus: authToggleUserStatus,
    updateUserSector: authUpdateUserSector,
    getRouteForSector: authGetRouteForSector
  };

  function renderRoute(route) {
    const templateId = APP_TEMPLATE_IDS[route];
    const template = templateId ? document.getElementById(templateId) : null;
    const app = document.getElementById("app");

    if (!template || !app) {
      document.body.innerHTML = "<main style='padding:32px;font-family:Arial,sans-serif'>Nao foi possivel carregar a tela solicitada.</main>";
      return;
    }

    document.body.className = "route-" + route;
    document.title = APP_PAGE_TITLES[route] || "Controle de Licitacao";
    app.innerHTML = template.innerHTML;
    authHydratePage();

    const codigoPagina = APP_PAGE_SCRIPTS[route];
    if (codigoPagina) {
      try {
        window.eval(codigoPagina + "\n//# sourceURL=" + route + ".runtime.js");
      } catch (erro) {
        console.error("Falha ao iniciar a tela:", route, erro);
        app.insertAdjacentHTML(
          "afterbegin",
          "<div style='margin:16px;padding:14px 16px;border-radius:12px;background:#fee2e2;color:#991b1b;font:600 14px Arial,sans-serif'>Erro ao carregar os botoes e scripts desta tela.</div>"
        );
      }
    }
  }

  function rerenderCurrentRoute() {
    const route = getCurrentRoute();
    const routeProtegida = authProtectRoute(route);
    if (!routeProtegida) return;
    renderRoute(routeProtegida);
  }

  function boot() {
    rerenderCurrentRoute();
  }

  window.addEventListener("hashchange", function () {
    boot();
  });

  window.addEventListener("storage", function (event) {
    if (event.key !== AUTH_REQUESTS_KEY && event.key !== AUTH_USERS_KEY) return;
    if (getCurrentRoute() !== "admin") return;
    rerenderCurrentRoute();
  });

  window.addEventListener("focus", function () {
    if (getCurrentRoute() !== "admin") return;
    rerenderCurrentRoute();
  });

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot, { once: true });
  } else {
    boot();
  }
})();
"@

Set-Content -LiteralPath (Join-Path $outputRoot "index.html") -Value $indexHtml -Encoding UTF8
Set-Content -LiteralPath (Join-Path $outputRoot "app.css") -Value $baseCss -Encoding UTF8
Set-Content -LiteralPath (Join-Path $outputRoot "app.js") -Value $appJs -Encoding UTF8

foreach ($entry in $legacyPages.GetEnumerator()) {
  $page = $entry.Key
  $route = $entry.Value
  $stub = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta http-equiv="refresh" content="0; url=index.html#$route" />
  <title>Redirecionando...</title>
</head>
<body>
  <script>
    window.location.replace("index.html#$route");
  </script>
</body>
</html>
"@
  Set-Content -LiteralPath (Join-Path $outputRoot $page) -Value $stub -Encoding UTF8
}
