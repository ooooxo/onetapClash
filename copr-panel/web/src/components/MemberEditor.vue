<script setup lang="ts">
import { ref } from 'vue'
import Modal from './Modal.vue'
import Switch from './Switch.vue'
import XDate from './XDate.vue'
import XSelect from './XSelect.vue'
import { store } from '../store'
import { ruuid, rb64 } from '../lib/rand'
import { buildClient } from '../lib/suiClient'
import { save as apiSave } from '../api/client'
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
const expiry = ref(src && /^\d{4}-\d{2}-\d{2}$/.test(src.exp) ? src.exp : '')
const desc = ref('')
const autoReset = ref(false)
const resetDays = ref('30')
const delayStart = ref(false)
const bindReality = ref(true)
const bindHy2 = ref(true)
const uuid = ref(ruuid())
const flow = ref('xtls-rprx-vision')
const pw = ref(rb64(16))
const ext = ref('')

const sub = () => `http://${store.domain}/get/${name.value || '<名称>'}`
const busy = ref(false)
async function save() {
  if (isEdit) { window.open(store.suiUrl(), '_blank'); toast('会员编辑走 s-ui(凭证不可回读,面板改会清空 config)'); emit('close'); return }
  const nm = name.value.trim()
  if (!nm) { toast('请填名称'); return }
  const inbounds = [...(bindHy2.value ? [1] : []), ...(bindReality.value ? [2] : [])]
  const expiryMs = expiry.value ? new Date(expiry.value + 'T00:00:00').getTime() : 0
  const obj = buildClient(nm, { inbounds, volumeGiB: Number(volume.value) || 0, expiryMs, uuid: uuid.value, hy2pw: pw.value, group: group.value })
  busy.value = true
  try {
    await apiSave('clients', 'new', obj)
    await store.load()
    toast('会员已创建 ' + nm)
    emit('close')
  } catch (e: any) { toast('创建失败: ' + (e?.message || e)) }
  busy.value = false
}
</script>

<template>
  <Modal wide @close="emit('close')">
    <div class="mh3">{{ isEdit ? '编辑会员 · ' + name : '新增会员' }}</div>
    <div class="msub">跨协议身份 · 配额 / 到期 / 自动重置 / 绑定节点</div>
    <div class="mtabs">
      <button :class="{ on: tab === 'basic' }" @click="tab = 'basic'">基础</button>
      <button :class="{ on: tab === 'config' }" @click="tab = 'config'">配置</button>
      <button :class="{ on: tab === 'links' }" @click="tab = 'links'">链接</button>
    </div>

    <div v-if="tab === 'basic'">
      <div class="swrow"><div class="tx"><b>启用</b></div><Switch v-model="enabled" /></div>
      <div class="frow"><div class="fld"><label>名称</label><input v-model="name" placeholder="例如 alice" /></div><div class="fld"><label>分组</label><input v-model="group" /></div></div>
      <div class="frow"><div class="fld"><label>流量上限 (GiB · 0 不限)</label><input v-model="volume" /></div><div class="fld"><label>到期</label><XDate v-model="expiry" /></div></div>
      <div class="fld"><label>描述</label><input v-model="desc" placeholder="可选备注" /></div>
      <div class="swrow"><div class="tx"><b>自动重置流量</b><span>每 N 天清零计数</span></div><Switch v-model="autoReset" /></div>
      <div v-if="autoReset" class="fld"><label>重置周期(天)</label><input v-model="resetDays" /></div>
      <div class="swrow"><div class="tx"><b>延迟启动</b><span>首次连接才开始计时到期</span></div><Switch v-model="delayStart" /></div>
      <label class="lb" style="display:block;margin:14px 0 8px">绑定节点</label>
      <div class="frow"><label class="chk"><input type="checkbox" v-model="bindReality" />VLESS · Reality</label><label class="chk"><input type="checkbox" v-model="bindHy2" />Hysteria2</label></div>
    </div>

    <div v-else-if="tab === 'config'">
      <div class="fnote" style="margin-bottom:14px">凭证按绑定协议自动生成,可手改。上线后对接 s-ui 全 15 协议凭证。</div>
      <div class="frow"><div class="fld gen"><label>VLESS UUID</label><input v-model="uuid" readonly /><button class="rg" @click="uuid = ruuid()">重新生成</button></div><div class="fld"><label>VLESS Flow</label><XSelect v-model="flow" :options="['xtls-rprx-vision', '(空)']" /></div></div>
      <div class="fld gen"><label>Hysteria2 密码</label><input v-model="pw" readonly /><button class="rg" @click="pw = rb64(16)">重新生成</button></div>
    </div>

    <div v-else>
      <div class="fld"><label>订阅链接(自动生成)</label><div class="url" style="margin-top:6px"><code>{{ sub() }}</code><button class="cpy" @click="copyText(sub())">复制</button></div><div class="fnote">clash 格式,经 converter 注入分流规则</div></div>
      <div class="fld"><label>外部链接(可选)</label><input v-model="ext" placeholder="vless://... 或第三方订阅 URL" /></div>
    </div>

    <div class="marow"><button class="btn" :disabled="busy" @click="save">{{ busy ? '处理中…' : (isEdit ? '保存修改' : '创建会员') }}</button><button class="gh" @click="emit('close')">取消</button></div>
  </Modal>
</template>
