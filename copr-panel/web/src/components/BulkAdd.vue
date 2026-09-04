<script setup lang="ts">
import { ref, computed } from 'vue'
import Modal from './Modal.vue'
import XDate from './XDate.vue'
import { toast } from '../ui'
import { store } from '../store'
import { buildClient } from '../lib/suiClient'
import { save as apiSave } from '../api/client'
const emit = defineEmits<{ (e: 'close'): void }>()
const names = ref('')
const volume = ref('0'); const expiry = ref(''); const group = ref('default')
// 绑定节点 = s-ui 真实入站 id,默认全选
const picked = ref<number[]>(store.nodes.map(n => n.id))
function togglePick(id: number) {
  const i = picked.value.indexOf(id)
  if (i >= 0) picked.value.splice(i, 1); else picked.value.push(id)
}
const count = computed(() => names.value.split('\n').map(s => s.trim()).filter(Boolean).length)
const busy = ref(false)
async function create() {
  const list = names.value.split('\n').map(s => s.trim()).filter(Boolean)
  if (!list.length) { toast('请填名称'); return }
  if (!picked.value.length) { toast('请至少选一个节点'); return }
  const expiryMs = expiry.value ? new Date(expiry.value + 'T00:00:00').getTime() : 0
  const clients = list.map(n => buildClient(n, { inbounds: [...picked.value], volumeGiB: Number(volume.value) || 0, expiryMs, group: group.value }))
  busy.value = true
  try {
    await apiSave('clients', 'addbulk', clients)  // s-ui 原生批量
    await store.load()
    toast(`批量创建 ${list.length} 个会员`)
    emit('close')
  } catch (e: any) { toast('批量失败: ' + (e?.message || e)) }
  busy.value = false
}
</script>
<template>
  <Modal wide @close="emit('close')">
    <div class="mh3">批量添加会员</div>
    <div class="msub">每行一个名称,共用下方配额/协议 · 对应 s-ui 的批量添加</div>
    <div class="fld"><label>名称列表(每行一个)</label><textarea v-model="names" rows="6" placeholder="alice&#10;bob&#10;carol" /><div class="fnote">{{ count }} 个</div></div>
    <div class="frow"><div class="fld"><label>流量上限 (GiB · 0 不限)</label><input v-model="volume" /></div><div class="fld"><label>到期</label><XDate v-model="expiry" /></div></div>
    <div class="fld"><label>分组</label><input v-model="group" /></div>
    <label class="lb" style="display:block;margin:14px 0 8px">绑定节点</label>
    <div v-if="store.nodes.length" class="frow">
      <label v-for="n in store.nodes" :key="n.id" class="chk">
        <input type="checkbox" :checked="picked.includes(n.id)" @change="togglePick(n.id)" />{{ n.name }} · {{ n.proto }}
      </label>
    </div>
    <div v-else class="fnote">还没有任何入站节点,建出来的会员不会有可用链接。</div>
    <div class="fnote">每人各自随机 UUID / 密码,订阅链接按名称自动生成。</div>
    <div class="marow"><button class="btn" :disabled="busy" @click="create">{{ busy ? '创建中…' : '批量创建' }}</button><button class="gh" @click="emit('close')">取消</button></div>
  </Modal>
</template>
