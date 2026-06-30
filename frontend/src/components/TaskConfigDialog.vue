<template>
  <el-dialog
    v-model="visible"
    :title="`配置任务 #${taskId}`"
    width="520px"
    :close-on-click-modal="false"
    @close="onClose"
  >
    <div v-if="loading" style="text-align:center;padding:40px;color:#909399">加载中…</div>

    <div v-else-if="task">
      <el-alert
        v-if="isRunning"
        type="warning"
        show-icon
        :closable="false"
        title="任务运行中，请先停止任务后再修改配置"
        style="margin:0 0 12px"
      />

      <el-form :model="form" label-width="100px" :disabled="isRunning">
        <el-form-item label="目标医生">
          <el-select v-model="form.doctor_code" filterable allow-create default-first-option
            clearable placeholder="搜索医生姓名/编码" style="width:100%">
            <el-option v-for="d in doctors" :key="d.doctor_code"
              :label="`${d.doctor_name || d.doctor_code}  (${d.doctor_code})`"
              :value="d.doctor_code">
              <span style="font-weight:500">{{ d.doctor_name || d.doctor_code }}</span>
              <span style="float:right;color:#909399;font-size:12px;margin-left:8px">{{ d.doctor_code }}</span>
            </el-option>
          </el-select>
        </el-form-item>

        <el-form-item label="目标日期">
          <el-date-picker v-model="form.lock_plan_date" type="date" value-format="YYYY-MM-DD"
            placeholder="锁号目标日期" style="width:100%" clearable />
        </el-form-item>

        <el-form-item label="就诊人">
          <el-select v-model="form.patient_id" clearable placeholder="默认取第一个就诊人" style="width:100%"
            :loading="patientsLoading">
            <el-option label="自动（第一个就诊人）" value="" />
            <el-option v-for="p in accountPatients" :key="p.id"
              :label="`${p.name}  ${p.gender || ''}  ${p.age != null ? p.age + '岁' : ''}`"
              :value="p.id" />
          </el-select>
        </el-form-item>

        <el-form-item label="代理模板">
          <el-select
            v-model="form.proxy_template_ids"
            multiple clearable
            placeholder="清空则该任务全部代理重置为系统默认；多选时按代理依次轮询"
            style="width:100%"
          >
            <el-option v-for="t in templates" :key="t.id" :label="t.name" :value="t.id">
              <span>{{ t.name }}</span>
              <span v-if="t.name === '默认配置'" style="color:#e6a23c;font-size:11px;margin-left:6px">默认</span>
              <span v-if="t.description" style="color:#909399;font-size:12px;margin-left:8px">{{ t.description }}</span>
            </el-option>
          </el-select>
          <div style="margin-top:4px;color:#909399;font-size:12px">
            保存后按代理 ID 顺序重新轮转套用到该任务当前全部代理
          </div>
        </el-form-item>
      </el-form>

      <div class="cfg-tip">
        <el-icon><InfoFilled /></el-icon>
        <span>查号窗口、锁号、通道等差异化配置已下沉到代理层，请在该任务下的代理行（⚙）或代理池中配置</span>
      </div>
    </div>

    <template #footer>
      <el-button @click="visible = false">关闭</el-button>
      <el-button type="primary" :disabled="isRunning" @click="save">保存</el-button>
    </template>
  </el-dialog>
</template>

<script setup>
import { ref, reactive, computed, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { InfoFilled } from '@element-plus/icons-vue'
import { getTask, updateTask, getDoctors, getProxyTemplates, getAccountPatients, getTaskStatus } from '@/api'

const props = defineProps({
  modelValue: { type: Boolean, default: false },
  taskId:     { type: Number, default: null },
})
const emit = defineEmits(['update:modelValue', 'saved', 'closed'])

const visible = computed({
  get: () => props.modelValue,
  set: v => emit('update:modelValue', v),
})

const loading = ref(false)
const task = ref(null)
const doctors = ref([])
const templates = ref([])
const accountPatients = ref([])
const patientsLoading = ref(false)
const runtimeStatus = reactive({ status: 'idle' })

const form = reactive({
  doctor_code: '',
  lock_plan_date: '',
  patient_id: '',
  proxy_template_ids: [],
})

const isRunning = computed(() =>
  ['running', 'initializing'].includes(runtimeStatus.status)
)

watch(() => props.modelValue, async (v) => {
  if (v && props.taskId != null) await load()
  if (!v) reset()
})

async function load() {
  loading.value = true
  try {
    const [t, dr, tmpls, st] = await Promise.all([
      getTask(props.taskId),
      getDoctors(),
      getProxyTemplates(),
      getTaskStatus(props.taskId).catch(() => ({ data: { status: 'idle' } })),
    ])
    task.value = t.data
    doctors.value = dr.data
    templates.value = tmpls.data || []
    runtimeStatus.status = st.data?.status || 'idle'
    Object.assign(form, {
      doctor_code:        t.data.doctor_code || '',
      lock_plan_date:     t.data.lock_plan_date || '',
      patient_id:         t.data.patient_id || '',
      // 后端 parseTask 已把 proxy_template_ids 解析为数组
      proxy_template_ids: Array.isArray(t.data.proxy_template_ids) ? [...t.data.proxy_template_ids] : [],
    })
    // 任务天生属于某账号，就诊人按任务自身 account_id 加载
    if (t.data.account_id != null) await loadPatients(t.data.account_id)
  } finally {
    loading.value = false
  }
}

async function loadPatients(accountId) {
  patientsLoading.value = true
  try {
    const r = await getAccountPatients(accountId)
    accountPatients.value = r.data || []
  } finally {
    patientsLoading.value = false
  }
}

function reset() {
  task.value = null
  Object.assign(form, { doctor_code: '', lock_plan_date: '', patient_id: '', proxy_template_ids: [] })
}

async function save() {
  if (!task.value) return
  try {
    // 带上 proxy_template_ids → 后端重新轮转套用到该任务全部代理
    await updateTask(task.value.id, {
      doctor_code: form.doctor_code || null,
      lock_plan_date: form.lock_plan_date || null,
      patient_id: form.patient_id || null,
      proxy_template_ids: form.proxy_template_ids,
    })
    ElMessage.success('已保存')
    emit('saved')
    visible.value = false
  } catch {
    /* 失败时保留弹窗，错误由拦截器提示 */
  }
}

function onClose() {
  emit('closed')
}
</script>

<style scoped>
.cfg-tip {
  margin-top: 12px;
  padding: 8px 12px;
  background: #f5f7fa;
  border-radius: 4px;
  color: #909399;
  font-size: 12px;
  display: flex;
  align-items: center;
  gap: 6px;
}
</style>
