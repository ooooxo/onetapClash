<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { toast } from '../ui'
import { convSatellites, convSetSatellites, convSyncSatellites } from '../api/client'
import Icon from './Icon.vue'

// 附属节点:别的服务器上的 onetapclash。会员只在本机管,converter 定时镜像过去,
// 订阅里追加它的节点(按前缀区分)。密码只写不读:留空 = 沿用已存的。
interface Sat { label: string; url: string; user: string; pass: string; has_pass?: boolean; status?: { ok: boolean; at: number; msg: string } | null }
const local = ref({ label: '', user: '', pass: '', has_pass: false })
const sats = ref<Sat[]>([])
const interval = ref(0)
const loadErr = ref('')
const busy = ref(false)

function apply(r: any) {
  local.value = { ...r.local, pass: '' }
  sats.value = r.satellites.map((s: any) => ({ ...s, pass: '' }))
  interval.value = r.interval
}
onMounted(async () => {
  try { apply(await convSatellites()) } catch (e: any) { loadErr.value = String(e?.message || e) }
})

const add = () => sats.value.push({ label: '', url: 'https://', user: '', pass: '' })
const ago = (t: number) => { const s = Math.round(Date.now() / 1000 - t); return s < 60 ? `${s} 秒前` : `${Math.round(s / 60)} 分钟前` }

async function saveAndSync() {
  busy.value = true
  try {
    await convSetSatellites({ local: local.value, satellites: sats.value })
    apply(await convSyncSatellites())
    const bad = sats.value.filter(s => s.status && !s.status.ok)
    toast(bad.length ? `已保存,${bad.length} 个附属节点同步失败,见状态` : '已保存并同步 · 客户端更新订阅即生效')
  } catch (e: any) { toast('保存失败: ' + (e?.message || e)) }
  busy.value = false
}
</script>
<template>
  <div class="panel">
    <div class="sect"><h3>附属节点</h3><div class="sp" />
      <button class="pri" :disabled="busy || !!loadErr" @click="saveAndSync"><Icon name="add" :size="14" />{{ busy ? '同步中…' : '保存并同步' }}</button>
    </div>
    <p class="hint">
      其他服务器上部署好的 onetapclash(bootstrap 跑完、有入站即可)。本机会员每 {{ interval }} 秒自动镜像过去
      (增删、启停、到期),订阅里追加它的节点;附属节点上用的流量同步时加回本机会员,一起算配额。
    </p>
    <div v-if="loadErr" class="fnote" style="color:var(--crit)">读取失败:{{ loadErr }}</div>
    <template v-else>
      <div class="ssec">本机</div>
      <div class="frow">
        <div class="fld"><label>节点前缀</label><input v-model="local.label" placeholder="如 🇯🇵东京(留空不加)" /></div>
        <div class="fld"><label>s-ui 账号</label><input v-model="local.user" placeholder="同步时读会员列表" /></div>
      </div>
      <div class="fld"><label>s-ui 密码</label><input v-model="local.pass" type="password" :placeholder="local.has_pass ? '已保存,留空不改' : '本机 s-ui 管理员密码'" /></div>

      <div v-for="(s, i) in sats" :key="i" class="sat">
        <div class="ssec">附属节点 {{ i + 1 }}
          <span v-if="s.status" class="chip" :class="s.status.ok ? 'on' : 'warn'">{{ s.status.ok ? '已同步' : '失败' }} · {{ ago(s.status.at) }}</span>
          <span v-else-if="s.has_pass" class="chip gray">未同步</span>
          <button class="del" @click="sats.splice(i, 1)"><Icon name="close" :size="12" /></button>
        </div>
        <div v-if="s.status" class="fnote" :style="{ color: s.status.ok ? 'var(--ink-3)' : 'var(--crit)', marginBottom: '10px' }">{{ s.status.msg }}</div>
        <div class="frow">
          <div class="fld"><label>节点前缀</label><input v-model="s.label" placeholder="如 🇺🇸洛杉矶" /></div>
          <div class="fld"><label>地址</label><input v-model="s.url" placeholder="https://la.example.com" /></div>
        </div>
        <div class="frow">
          <div class="fld"><label>s-ui 账号</label><input v-model="s.user" /></div>
          <div class="fld"><label>s-ui 密码</label><input v-model="s.pass" type="password" :placeholder="s.has_pass ? '已保存,留空不改' : '附属节点管理员密码'" /></div>
        </div>
      </div>
      <button class="addr" @click="add"><Icon name="add" :size="12" />添加附属节点</button>
    </template>
  </div>
</template>
<style scoped>
.hint{font-size:12px;color:var(--ink-3);margin-bottom:6px;line-height:1.6}
.ssec .chip{text-transform:none;letter-spacing:0}
.ssec .del{order:3}
.del{width:26px;height:26px;flex:none;border-radius:var(--r-xs);background:var(--inset);color:var(--ink-4);display:flex;align-items:center;justify-content:center}
.del:hover{color:var(--crit)}
.addr{display:flex;align-items:center;gap:5px;font-size:12px;color:var(--ink-3);padding:7px 10px;border-radius:var(--r-xs);background:var(--inset);margin-top:4px}
.addr:hover{color:var(--accent-ink)}
@media (max-width:820px){.del{width:44px;height:44px}.fld input{font-size:16px}}
</style>
