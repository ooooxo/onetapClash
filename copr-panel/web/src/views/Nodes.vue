<script setup lang="ts">
import { store } from '../store'
import { ui } from '../ui'
import Icon from '../components/Icon.vue'
</script>
<template>
  <div class="sect"><h3 style="font-size:15px;font-weight:650">节点</h3><div class="sp" style="flex:1" />
    <button class="pri" @click="ui.nodeOpen = true"><Icon name="add" :size="15" />开设节点</button>
  </div>
  <div class="grid g2">
    <div v-for="n in store.nodes" :key="n.name" class="panel">
      <div class="nh"><div class="ti"><Icon :name="n.proto === 'vless' ? 'shield' : 'bolt'" :size="20" /></div>
        <div style="flex:1"><b>{{ n.name }}</b><br><span>:{{ n.port }} · {{ n.net }}</span></div>
        <span class="chip on">在线</span>
      </div>
      <div class="kv"><span>协议</span><b>{{ n.proto }}</b></div>
      <div class="kv"><span>端口</span><b>{{ n.port }} / {{ n.net }}</b></div>
    </div>
  </div>
  <div class="panel" style="margin-top:16px"><div class="sect"><h3>提示</h3></div>
    <p style="font-size:13px;color:var(--ink-3);line-height:1.7">开设 / 改节点会让 s-ui 重载 sing-box,在线用户短暂重连。加 / 删会员通常不影响连接。</p>
  </div>
</template>
<style scoped>
.pri{display:flex;align-items:center;gap:7px;background:var(--accent);color:#fff;border-radius:var(--r-sm);padding:9px 15px;font-size:13px;font-weight:650}
.nh{display:flex;align-items:center;gap:11px;margin-bottom:16px}
.nh .ti{width:38px;height:38px;border-radius:var(--r-md);background:var(--accent-soft);color:var(--accent);display:flex;align-items:center;justify-content:center}
.nh b{font-size:15px;font-weight:650}.nh span{font-size:11px;color:var(--ink-4)}
.kv{display:flex;justify-content:space-between;padding:7px 0;font-size:13px}.kv+.kv{border-top:1px solid var(--hairline)}
.kv span{color:var(--ink-3)}.kv b{font-weight:600;font-family:var(--font-mono);font-size:12px}
</style>
