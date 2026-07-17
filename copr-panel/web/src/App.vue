<script setup lang="ts">
import { ref, onMounted } from 'vue'
import Icon from './components/Icon.vue'
import { store, type ViewId } from './store'
import { ui } from './ui'
import Dashboard from './views/Dashboard.vue'
import Nodes from './views/Nodes.vue'
import Members from './views/Members.vue'
import Sub from './views/Sub.vue'
import Traffic from './views/Traffic.vue'
import Settings from './views/Settings.vue'
import NodeEditor from './components/NodeEditor.vue'
import MemberEditor from './components/MemberEditor.vue'
import BulkAdd from './components/BulkAdd.vue'
import MemberDrawer from './components/MemberDrawer.vue'
import Toast from './components/Toast.vue'
import { login } from './api/client'
function editFromDrawer(name: string) { ui.drawerName = undefined; ui.memberEditName = name }

const NAV: { id: ViewId; label: string; icon: string }[] = [
  { id: 'dash', label: '看板', icon: 'dashboard' },
  { id: 'nodes', label: '节点', icon: 'nodes' },
  { id: 'members', label: '会员', icon: 'members' },
  { id: 'sub', label: '订阅分流', icon: 'sub' },
  { id: 'traffic', label: '流量', icon: 'traffic' },
  { id: 'settings', label: '设置', icon: 'settings' },
]
const VIEWS: Record<ViewId, any> = { dash: Dashboard, nodes: Nodes, members: Members, sub: Sub, traffic: Traffic, settings: Settings }
const SUB: Record<ViewId, string> = { dash: 'copr.site · Reality + Hysteria2', nodes: '入站与协议', members: '订阅 · 流量 · 到期', sub: '地址与模块化规则', traffic: '用量统计', settings: '面板与安全' }

const user = ref('')
const pass = ref('')
const loggingIn = ref(false)
const loginErr = ref('')
async function doLogin() {
  loggingIn.value = true; loginErr.value = ''
  try {
    const res: any = await login(user.value, pass.value)
    if (res && res.success === false) { loginErr.value = res.msg || '账号或密码错误'; loggingIn.value = false; return }
    await store.load(); store.loggedIn = true
  } catch {
    // fetch 抛错 = 后端不可达(本地无后端)→ 演示模式;线上不会走到这
    store.live = false; store.loggedIn = true
  }
  loggingIn.value = false
}
// 复用 s-ui 会话:若 cookie 仍有效,自动进入,免每次重登
onMounted(async () => { try { await store.load() } catch { /* not logged in */ } if (store.live) store.loggedIn = true })
</script>

<template>
  <div v-if="!store.loggedIn" class="login">
    <div class="lgc">
      <div class="brand"><div class="bi"><Icon name="shield" :size="21" /></div>
        <div><h1>{{ store.domain }}</h1><div class="sub">节点管理面板</div></div>
      </div>
      <div class="fld"><label>用户名</label><input v-model="user" autocomplete="off" placeholder="s-ui 账号" /></div>
      <div class="fld"><label>密码</label><input v-model="pass" type="password" placeholder="s-ui 密码" @keydown.enter="doLogin" /></div>
      <div v-if="loginErr" class="lerr">{{ loginErr }}</div>
      <button class="btn" :disabled="loggingIn" @click="doLogin">{{ loggingIn ? '登录中…' : '登录' }}</button>
      <div class="tip">用 s-ui 管理员账号登录</div>
    </div>
  </div>

  <div v-else class="app">
    <aside>
      <div class="abrand"><div class="bi"><Icon name="shield" :size="17" /></div>
        <div><b>{{ store.domain }}</b><span>sing-box · s-ui</span></div>
      </div>
      <nav>
        <button v-for="n in NAV" :key="n.id" :class="{ on: store.view === n.id }" @click="store.view = n.id">
          <Icon :name="n.icon" :size="18" />{{ n.label }}
        </button>
      </nav>
      <div class="spacer" />
      <div class="auser"><div class="av">A</div><div><div class="un">admin</div><div class="ur">管理员</div></div>
        <button class="lo" aria-label="退出" @click="store.loggedIn = false"><Icon name="logout" :size="16" /></button>
      </div>
    </aside>

    <main>
      <header class="top">
        <div><h2>{{ NAV.find(n => n.id === store.view)?.label }}</h2><div class="tsub">{{ SUB[store.view] }}</div></div>
        <div class="sp" />
        <span class="chip" :class="store.live ? 'on' : 'gray'">{{ store.live ? '线上' : '演示数据' }}</span>
        <button class="icbtn" aria-label="主题" @click="store.toggleTheme()"><Icon name="theme" :size="18" /></button>
      </header>
      <div class="view"><component :is="VIEWS[store.view]" /></div>
    </main>
  </div>

  <NodeEditor v-if="ui.nodeOpen" @close="ui.nodeOpen = false" />
  <MemberEditor v-if="ui.memberEditName !== undefined" :edit-name="ui.memberEditName" @close="ui.memberEditName = undefined" />
  <BulkAdd v-if="ui.bulkOpen" @close="ui.bulkOpen = false" />
  <MemberDrawer v-if="ui.drawerName" :name="ui.drawerName" @close="ui.drawerName = undefined" @edit="editFromDrawer" />
  <Toast />
</template>

<style scoped>
.login{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;padding:20px;background:radial-gradient(120% 80% at 50% -10%,color-mix(in srgb,var(--accent) 7%,var(--bg-window)),var(--bg-window))}
.lgc{width:min(380px,100%);background:var(--panel);border-radius:var(--r-xl);padding:34px 30px;box-shadow:var(--shadow-lg);animation:fu .5s var(--ease-out) both}
.brand{display:flex;align-items:center;gap:11px;margin-bottom:26px}
.bi{width:38px;height:38px;border-radius:var(--r-md);background:var(--accent);display:flex;align-items:center;justify-content:center;color:#fff;flex:none}
.lgc h1{font-size:18px;font-weight:700}.lgc .sub{font-size:12px;color:var(--ink-3);margin-top:2px}
.fld{margin-bottom:14px}
.fld label{display:block;font-size:12px;font-weight:600;color:var(--ink-3);margin-bottom:6px}
.fld input{width:100%;background:var(--inset);border:1px solid transparent;border-radius:var(--r-sm);padding:11px 13px;color:var(--ink);font-size:14px;transition:border-color var(--t-fast)}
.fld input:focus{outline:none;border-color:var(--accent)}
.btn{width:100%;background:var(--accent);color:#fff;border-radius:var(--r-sm);padding:12px;font-size:14px;font-weight:650;transition:filter var(--t-fast),transform var(--t-fast) var(--spring)}
.btn:hover{filter:brightness(1.08)}.btn:active{transform:scale(.98)}
.lerr{font-size:12px;color:var(--crit);text-align:center;margin-bottom:12px;font-weight:600}
.tip{font-size:11px;color:var(--ink-4);text-align:center;margin-top:16px;line-height:1.5}
.app{display:grid;grid-template-columns:224px 1fr;min-height:100vh}
aside{background:var(--sidebar);border-right:1px solid var(--sep);display:flex;flex-direction:column;padding:18px 12px;position:sticky;top:0;height:100vh}
.abrand{display:flex;align-items:center;gap:10px;padding:6px 8px 20px}
.abrand .bi{width:30px;height:30px;border-radius:var(--r-sm)}
.abrand b{font-size:14px;font-weight:700}.abrand span{font-size:11px;color:var(--ink-4);display:block}
nav{display:flex;flex-direction:column;gap:2px}
nav button{display:flex;align-items:center;gap:11px;padding:10px 11px;border-radius:var(--r-sm);color:var(--ink-3);font-size:14px;font-weight:550;text-align:left;transition:background var(--t-fast),color var(--t-fast)}
nav button:hover{background:var(--hover);color:var(--ink-2)}
nav button.on{background:var(--accent-soft);color:var(--accent-ink)}
.spacer{flex:1}
.auser{display:flex;align-items:center;gap:10px;padding:10px 8px;border-top:1px solid var(--sep);margin-top:8px}
.auser .av{width:30px;height:30px;border-radius:var(--r-pill);background:var(--panel-2);display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:700;color:var(--ink-2)}
.auser .un{font-size:13px;font-weight:600}.auser .ur{font-size:11px;color:var(--ink-4)}
.auser .lo{margin-left:auto;color:var(--ink-3);padding:6px;border-radius:var(--r-xs)}
.auser .lo:hover{background:var(--hover);color:var(--ink)}
main{background:var(--bg-content);min-width:0;display:flex;flex-direction:column}
.top{display:flex;align-items:center;gap:14px;padding:18px 28px;border-bottom:1px solid var(--sep);position:sticky;top:0;background:color-mix(in srgb,var(--bg-content) 88%,transparent);backdrop-filter:blur(10px);z-index:5}
.top h2{font-size:18px;font-weight:700}.top .tsub{font-size:12px;color:var(--ink-3);margin-top:1px}.top .sp{flex:1}
.icbtn{width:36px;height:36px;border-radius:var(--r-sm);color:var(--ink-3);display:flex;align-items:center;justify-content:center;transition:background var(--t-fast),color var(--t-fast)}
.icbtn:hover{background:var(--hover);color:var(--ink)}
.view{padding:26px 28px;flex:1;animation:fu .34s var(--ease-out) both}
@media (max-width:820px){.app{grid-template-columns:1fr}aside{display:none}}
</style>
