<script setup lang="ts">
import { ref, onMounted } from 'vue'
import Modal from './Modal.vue'
import Switch from './Switch.vue'
import XDate from './XDate.vue'
import XSelect from './XSelect.vue'
import { store } from '../store'
import { ruuid, rb64 } from '../lib/rand'
import { buildClient } from '../lib/suiClient'
import { save as apiSave, getClient } from '../api/client'
import { copyText } from '../lib/qr'
import { toast } from '../ui'

const props = defineProps<{ editName?: string }>()
const emit = defineEmits<{ (e: 'close'): void }>()
const isEdit = !!props.editName
const src = isEdit ? store.members.find(m => m.name === props.editName) : undefined

const tab = ref<'basic' | 'config' | 'links'>('basic')
const enabled = ref(true)
const name = ref(src?.name || '')
const group = ref('default')
const volume = ref('0')
const expiry = ref('')
const desc = ref('')
const autoReset = ref(false)
const resetDays = ref('30')
const delayStart = ref(false)
// 绑定节点 = s-ui 真实入站,默认全选;没有入站时不给建(建了也是死链接)
const picked = ref<number[]>(store.nodes.map(n => n.id))
function togglePick(id: number) {
  const i = picked.value.indexOf(id)
  if (i >= 0) picked.value.splice(i, 1); else picked.value.push(id)
}
const uuid = ref(ruuid())
const flow = ref('xtls-rprx-vision')
const pw = ref(rb64(16))
const ext = ref('')

// 编辑模式保存的是「取回来的整条记录」—— 尤其 config(各协议凭证)必须原样带回去。
// 只有 /api/clients?id=N 会返回 config,列表接口不返回;不带 config 直接 edit
// 会把凭证清空,已发出去的链接全部失效。
const original = ref<any>(null)
const loading = ref(isEdit)
const loadErr = ref('')

onMounted(async () => {
  if (!isEdit || src?.id == null) { loading.value = false; return }
  try {
    const c = await getClient(src.id)
    if (!c) throw new Error('读不到该会员')
    original.value = c
    enabled.value = !!c.enable
    name.value = c.name
    group.value = c.group || ''
    volume.value = String(Math.round((Number(c.volume) || 0) / 1073741824))
    desc.value = c.desc || ''
    autoReset.value = !!c.autoReset
    resetDays.value = String(c.resetDays || 30)
    delayStart.value = !!c.delayStart
    picked.value = Array.isArray(c.inbounds) ? [...c.inbounds] : []
    const e = Number(c.expiry)
    if (e > 0) expiry.value = new Date(e > 1e12 ? e : e * 1000).toISOString().slice(0, 10)
    uuid.value = c.config?.vless?.uuid || uuid.value
    flow.value = c.config?.vless?.flow || '(空)'
    pw.value = c.config?.hysteria2?.password || pw.value
    ext.value = (c.links || []).filter((l: any) => l.type !== 'local').map((l: any) => l.uri).join('\n')
  } catch (e: any) {
    loadErr.value = String(e?.message || e)
  }
  loading.value = false
})

const sub = () => store.subUrl(name.value || '<名称>')
const busy = ref(false)
async function save() {
  const nm = name.value.trim()
  if (!nm) { toast('请填名称'); return }
  if (!picked.value.length) { toast('请至少选一个节点'); return }
  const expiryMs = expiry.value ? new Date(expiry.value + 'T00:00:00').getTime() : 0
  const fl = flow.value === '(空)' ? '' : flow.value
  const extLinks = ext.value.split('\n').map(s => s.trim()).filter(Boolean)

  let obj: any
  if (isEdit) {
    if (!original.value) { toast('原始记录没读到,不能保存(会清空凭证)'); return }
    // 在整条记录上就地改,config 原样保留;只覆盖用户在表单里动过的凭证字段
    obj = { ...original.value }
    obj.enable = enabled.value
    obj.name = nm
    obj.group = group.value
    obj.desc = desc.value
    obj.volume = Math.round((Number(volume.value) || 0) * 1073741824)
    obj.expiry = expiryMs
    obj.autoReset = autoReset.value
    obj.resetDays = autoReset.value ? (Number(resetDays.value) || 30) : 0
    obj.delayStart = delayStart.value
    obj.inbounds = [...picked.value]
    obj.config = { ...(original.value.config || {}) }
    if (obj.config.vless) obj.config.vless = { ...obj.config.vless, uuid: uuid.value, flow: fl }
    if (obj.config.hysteria2) obj.config.hysteria2 = { ...obj.config.hysteria2, password: pw.value }
    obj.links = [
      ...(original.value.links || []).filter((l: any) => l.type === 'local'),
      ...extLinks.map(uri => ({ remark: 'external', type: 'external', uri })),
    ]
  } else {
    obj = buildClient(nm, {
      inbounds: [...picked.value], volumeGiB: Number(volume.value) || 0, expiryMs,
      uuid: uuid.value, hy2pw: pw.value, group: group.value,
      enable: enabled.value, desc: desc.value, flow: fl,
      autoReset: autoReset.value, resetDays: Number(resetDays.value) || 30,
      delayStart: delayStart.value, extLinks,
    })
  }

  busy.value = true
  try {
    const r: any = await apiSave('clients', isEdit ? 'edit' : 'new', obj)
    if (r && r.success === false) throw new Error(r.msg || '保存失败')
    await store.load()
    toast((isEdit ? '已保存 ' : '会员已创建 ') + nm)
    emit('close')
  } catch (e: any) { toast((isEdit ? '保存失败: ' : '创建失败: ') + (e?.message || e)) }
  busy.value = false
}
</script>

<template>
  <Modal wide @close="emit('close')">
    <div class="mh3">{{ isEdit ? '编辑会员 · ' + name : '新增会员' }}</div>
    <div class="msub">跨协议身份 · 配额 / 到期 / 自动重置 / 绑定节点</div>
    <div v-if="loading" class="fnote" style="padding:24px 0;text-align:center">读取会员配置中…</div>
    <div v-else-if="loadErr" class="lerr" style="padding:24px 0;text-align:center">{{ loadErr }}</div>
    <template v-else>
      <div class="mtabs">
        <button :class="{ on: tab === 'basic' }" @click="tab = 'basic'">基础</button>
        <button :class="{ on: tab === 'config' }" @click="tab = 'config'">配置</button>
        <button :class="{ on: tab === 'links' }" @click="tab = 'links'">链接</button>
      </div>

      <div v-if="tab === 'basic'">
        <div class="swrow"><div class="tx"><b>启用</b><span>停用后保留配置但连不上</span></div><Switch v-model="enabled" /></div>
        <div class="frow"><div class="fld"><label>名称</label><input v-model="name" placeholder="例如 alice" /></div><div class="fld"><label>分组</label><input v-model="group" /></div></div>
        <div class="frow"><div class="fld"><label>流量上限 (GiB · 0 不限)</label><input v-model="volume" /></div><div class="fld"><label>到期</label><XDate v-model="expiry" /></div></div>
        <div class="fld"><label>描述</label><input v-model="desc" placeholder="可选备注" /></div>
        <div class="swrow"><div class="tx"><b>自动重置流量</b><span>每 N 天清零计数</span></div><Switch v-model="autoReset" /></div>
        <div v-if="autoReset" class="fld"><label>重置周期(天)</label><input v-model="resetDays" /></div>
        <div class="swrow"><div class="tx"><b>延迟启动</b><span>首次连接才开始计时到期</span></div><Switch v-model="delayStart" /></div>
        <label class="lb" style="display:block;margin:14px 0 8px">绑定节点</label>
        <div v-if="store.nodes.length" class="frow">
          <label v-for="n in store.nodes" :key="n.id" class="chk">
            <input type="checkbox" :checked="picked.includes(n.id)" @change="togglePick(n.id)" />{{ n.name }} · {{ n.proto }}
          </label>
        </div>
        <div v-else class="fnote">还没有任何入站节点 —— 先跑 <code>ensure-nodes.sh</code> 或在 s-ui 建节点,否则建出来的会员没有可用链接。</div>
      </div>

      <div v-else-if="tab === 'config'">
        <div class="fnote" style="margin-bottom:14px">
          创建时会为 s-ui 支持的全部协议各生成一套凭证。这里只改下面两项,其余协议的凭证原样保留。
        </div>
        <div class="frow"><div class="fld gen"><label>VLESS UUID</label><input v-model="uuid" /><button class="rg" @click="uuid = ruuid()">重新生成</button></div><div class="fld"><label>VLESS Flow</label><XSelect v-model="flow" :options="['xtls-rprx-vision', '(空)']" /></div></div>
        <div class="fld gen"><label>Hysteria2 密码</label><input v-model="pw" /><button class="rg" @click="pw = rb64(16)">重新生成</button></div>
        <div v-if="isEdit" class="fnote" style="margin-top:10px;color:var(--warn)">改凭证会让该会员已导入的旧配置失效,需要重新拉一次订阅。</div>
      </div>

      <div v-else>
        <div class="fld"><label>订阅链接(自动生成)</label><div class="url" style="margin-top:6px"><code>{{ sub() }}</code><button class="cpy" @click="copyText(sub())">复制</button></div><div class="fnote">clash 格式,经 converter 注入分流规则</div></div>
        <div class="fld"><label>外部链接(可选,每行一条)</label><textarea v-model="ext" rows="3" placeholder="vless://... 或第三方订阅 URL" /><div class="fnote">会并入该会员的订阅;s-ui 重建节点链接时不会冲掉它们。</div></div>
      </div>

      <div class="marow"><button class="btn" :disabled="busy" @click="save">{{ busy ? '处理中…' : (isEdit ? '保存修改' : '创建会员') }}</button><button class="gh" @click="emit('close')">取消</button></div>
    </template>
  </Modal>
</template>
