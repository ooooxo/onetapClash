<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { store } from '../store'
import { settings as apiSettings, convRules } from '../api/client'

// 全部取真实值:面板设置来自 s-ui /api/settings,converter 状态靠实际请求。
// 拿不到就显示"读取失败",不编造。
const s = ref<Record<string, any> | null>(null)
const sErr = ref('')
const convOk = ref<boolean | null>(null)

onMounted(async () => {
  try {
    const r: any = await apiSettings()
    s.value = r?.obj ?? r
    if (s.value?.webPort) { store.suiPort = Number(s.value.webPort); store.suiPath = s.value.webPath || '/app/' }
  } catch (e: any) { sErr.value = String(e?.message || e) }
  try { await convRules(); convOk.value = true } catch { convOk.value = false }
})
const isHttps = location.protocol === 'https:'
const v = (k: string, d = '—') => (s.value && s.value[k] !== undefined && s.value[k] !== '' ? String(s.value[k]) : d)
</script>
<template>
  <div class="grid g2">
    <div class="panel">
      <div class="sect"><h3>面板与订阅</h3><div class="sp" /><span class="chip" :class="s ? 'on' : 'gray'">{{ s ? '实时' : (sErr ? '读取失败' : '读取中…') }}</span></div>
      <div class="kv"><span>Vue 面板</span><b>{{ store.domain }}/panel/</b></div>
      <div class="kv"><span>s-ui 原面板</span><b>{{ store.suiUrl() }}</b></div>
      <div class="kv"><span>面板端口 / 路径</span><b>{{ v('webPort') }} · {{ v('webPath') }}</b></div>
      <div class="kv"><span>订阅端口 / 路径</span><b>{{ v('subPort') }} · {{ v('subPath') }}</b></div>
      <div class="kv"><span>对外订阅</span><b>{{ store.subUrl('<会员名>') }}</b></div>
      <div class="kv"><span>时区</span><b>{{ v('timeLocation') }}</b></div>
      <div v-if="sErr" class="kv"><span>错误</span><b style="color:var(--crit)">{{ sErr }}</b></div>
    </div>
    <div class="panel">
      <div class="sect"><h3>运行状态</h3></div>
      <div class="kv"><span>s-ui 后端</span><b :style="{ color: store.live ? 'var(--online)' : 'var(--crit)' }">{{ store.live ? '已连接' : '未连接' }}</b></div>
      <div class="kv"><span>converter 分流 API</span>
        <b :style="{ color: convOk === false ? 'var(--crit)' : convOk ? 'var(--online)' : 'var(--ink-3)' }">
          {{ convOk === null ? '检测中…' : convOk ? '可用' : '不可用' }}
        </b>
      </div>
      <div class="kv"><span>面板传输</span>
        <b :style="{ color: isHttps ? 'var(--online)' : 'var(--warn)' }">
          {{ isHttps ? 'HTTPS' : 'HTTP 明文,建议配证书' }}
        </b>
      </div>
      <div class="kv"><span>入站节点</span><b>{{ store.nodes.length }} 个</b></div>
      <div class="kv"><span>会员</span><b>{{ store.members.length }} 人</b></div>
    </div>
  </div>
</template>
<style scoped>
.kv{display:flex;justify-content:space-between;gap:12px;padding:9px 0;font-size:13px}.kv+.kv{border-top:1px solid var(--hairline)}
.kv span{color:var(--ink-3);flex:none}
.kv b{font-weight:600;font-family:var(--font-mono);font-size:12px;text-align:right;word-break:break-all}
</style>
