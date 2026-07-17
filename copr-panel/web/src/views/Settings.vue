<script setup lang="ts">
import { store } from '../store'
</script>
<template>
  <div class="grid g2">
    <div class="panel">
      <div class="sect"><h3>面板与订阅</h3></div>
      <div class="kv"><span>面板地址</span><b>{{ store.domain }}:2020/app/</b></div>
      <div class="kv"><span>订阅端口</span><b>2096 /sub/</b></div>
      <div class="kv"><span>converter</span><b>127.0.0.1:25501</b></div>
      <div class="kv"><span>域名</span><b>{{ store.domain }}</b></div>
    </div>
    <div class="panel">
      <div class="sect"><h3>安全</h3><div class="sp" /><span class="chip warn">2 项待修</span></div>
      <div class="kv"><span>订阅 TLS</span><b style="color:var(--warn)">HTTP 明文,建议启用</b></div>
      <div class="kv"><span>管理密钥</span><b style="color:var(--warn)">converter 密钥过弱</b></div>
      <div class="kv"><span>/admin 访问</span><b>建议限本地</b></div>
    </div>
  </div>
</template>
<style scoped>
.kv{display:flex;justify-content:space-between;padding:9px 0;font-size:13px}.kv+.kv{border-top:1px solid var(--hairline)}
.kv span{color:var(--ink-3)}.kv b{font-weight:600}
</style>
