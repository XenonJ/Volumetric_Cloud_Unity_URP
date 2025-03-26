using UnityEngine;

[ExecuteAlways]
public class CloudFlowController : MonoBehaviour
{
    [Header("Flow Settings")]
    [Tooltip("云的流动速度")]
    public Vector3 flowSpeed = new Vector3(0.1f, 0.05f, 0.08f);

    [Tooltip("时间缩放因子")]
    [Range(0.1f, 5.0f)]
    public float timeScale = 1.0f;

    [Tooltip("流动主方向")]
    public Vector3 flowDirection = new Vector3(1f, 0f, 0.5f);

    [Tooltip("湍流强度")]
    [Range(0f, 2.0f)]
    public float turbulenceScale = 0.5f;

    [Header("Cloud Shape Settings")]
    [Tooltip("密度阈值 - 值越高云越稀疏")]
    [Range(0f, 2.0f)]
    public float densityThreshold = 0.6f;

    [Tooltip("密度乘数 - 控制云的整体密度")]
    [Range(0.1f, 20.0f)]
    public float densityMultiplier = 1.0f;

    [Tooltip("云的锐利度 - 值越高边缘越清晰")]
    [Range(0.1f, 10.0f)]
    public float cloudSharpness = 1.5f;

    [Tooltip("细节强度 - 控制小尺度噪声对云形状的影响")]
    [Range(0.1f, 2.0f)]
    public float detailStrength = 0.7f;

    [Tooltip("噪声缩放 - 控制噪声的整体尺度")]
    [Range(0.1f, 5.0f)]
    public float noiseScale = 1.5f;

    [Tooltip("高度衰减 - 控制云随高度变化的程度")]
    [Range(0f, 10.0f)]
    public float heightFalloff = 3.0f;

    [Header("Performance Settings")]
    [Tooltip("光线步进次数 - 影响渲染质量和性能")]
    [Range(8, 64)]
    public int stepCount = 32;

    [Tooltip("最大步进次数 - 着色器内部限制")]
    [Range(8, 64)]
    public int maxSteps = 64;

    [Tooltip("透明度提前退出阈值 - 值越大性能越好但可能影响质量")]
    [Range(0.01f, 0.5f)]
    public float transparencyThreshold = 0.1f;

    [Header("Animation Settings")]
    [Tooltip("是否启用自动方向变化")]
    public bool enableDirectionChange = false;

    [Tooltip("方向变化周期 (秒)")]
    public float directionChangePeriod = 20.0f;

    [Tooltip("方向变化强度")]
    [Range(0.1f, 1.0f)]
    public float directionChangeAmount = 0.3f;

    private Renderer _renderer;
    private MaterialPropertyBlock _propBlock;
    private Vector3 _baseFlowDirection;
    private float _directionTimer = 0f;

    [Header("Presets")]
    [Tooltip("应用积云预设 - 松散蓬松的云")]
    public bool applyCumulusPreset = false;

    [Tooltip("应用层积云预设 - 平坦分层的云")]
    public bool applyStratocumulusPreset = false;

    [Tooltip("应用卷云预设 - 高空薄云")]
    public bool applyCirrusPreset = false;

    [Tooltip("应用低性能预设 - 更快的渲染，较低质量")]
    public bool applyLowPerformancePreset = false;

    [Tooltip("应用高性能预设 - 更高质量，较慢的渲染")]
    public bool applyHighPerformancePreset = false;

    void Awake()
    {
        _renderer = GetComponent<Renderer>();
        _propBlock = new MaterialPropertyBlock();
        _baseFlowDirection = flowDirection;
    }

    void Start()
    {
        UpdateCloudProperties();
    }

    void Update()
    {
        if (enableDirectionChange)
        {
            AnimateFlowDirection();
        }
        
        // 检查是否应用预设
        CheckPresets();
        
        UpdateCloudProperties();
    }

    void OnValidate()
    {
        if (_renderer == null)
            _renderer = GetComponent<Renderer>();

        if (_propBlock == null)
            _propBlock = new MaterialPropertyBlock();

        _baseFlowDirection = flowDirection;
        
        // 检查是否应用预设
        CheckPresets();
        
        UpdateCloudProperties();
    }

    void CheckPresets()
    {
        // 积云预设 - 松散、蓬松的云
        if (applyCumulusPreset)
        {
            densityThreshold = 0.65f;
            densityMultiplier = 2.0f;
            cloudSharpness = 2.0f;
            detailStrength = 0.8f;
            noiseScale = 1.8f;
            heightFalloff = 4.0f;
            applyCumulusPreset = false;
        }
        
        // 层积云预设 - 平坦、层状的云
        if (applyStratocumulusPreset)
        {
            densityThreshold = 0.4f;
            densityMultiplier = 1.5f;
            cloudSharpness = 1.2f;
            detailStrength = 0.5f;
            noiseScale = 1.3f;
            heightFalloff = 8.0f;
            applyStratocumulusPreset = false;
        }
        
        // 卷云预设 - 高空、飘逸的云
        if (applyCirrusPreset)
        {
            densityThreshold = 0.8f;
            densityMultiplier = 0.8f;
            cloudSharpness = 0.8f;
            detailStrength = 1.5f;
            noiseScale = 2.2f;
            heightFalloff = 1.5f;
            applyCirrusPreset = false;
        }
        
        // 低性能预设 - 更快的渲染
        if (applyLowPerformancePreset)
        {
            stepCount = 16;
            maxSteps = 24;
            transparencyThreshold = 0.2f;
            applyLowPerformancePreset = false;
        }
        
        // 高性能预设 - 更高质量
        if (applyHighPerformancePreset)
        {
            stepCount = 48;
            maxSteps = 64;
            transparencyThreshold = 0.05f;
            applyHighPerformancePreset = false;
        }
    }

    void AnimateFlowDirection()
    {
        _directionTimer += Time.deltaTime;
        
        // 创建周期性的方向变化
        float phase = (_directionTimer / directionChangePeriod) * Mathf.PI * 2;
        
        // 使用正弦和余弦函数创建循环变化
        Vector3 directionOffset = new Vector3(
            Mathf.Sin(phase) * directionChangeAmount,
            Mathf.Cos(phase * 0.7f) * directionChangeAmount,
            Mathf.Sin(phase * 1.3f) * directionChangeAmount
        );
        
        // 应用变化到流动方向
        flowDirection = _baseFlowDirection + directionOffset;
        flowDirection.Normalize(); // 保持方向向量的单位长度
    }

    void UpdateCloudProperties()
    {
        // 获取当前Renderer的PropertyBlock
        _renderer.GetPropertyBlock(_propBlock);

        // 更新流动相关参数
        _propBlock.SetVector("_FlowSpeed", new Vector4(flowSpeed.x, flowSpeed.y, flowSpeed.z, 0));
        _propBlock.SetFloat("_TimeScale", timeScale);
        _propBlock.SetVector("_FlowDirection", new Vector4(flowDirection.x, flowDirection.y, flowDirection.z, 0));
        _propBlock.SetFloat("_TurbulenceScale", turbulenceScale);
        
        // 更新云形状相关参数
        _propBlock.SetFloat("_DensityThreshold", densityThreshold);
        _propBlock.SetFloat("_DensityMultiplier", densityMultiplier);
        _propBlock.SetFloat("_CloudSharpness", cloudSharpness);
        _propBlock.SetFloat("_DetailStrength", detailStrength);
        _propBlock.SetFloat("_NoiseScale", noiseScale);
        _propBlock.SetFloat("_HeightFalloff", heightFalloff);
        
        // 更新性能相关参数
        _propBlock.SetInt("_StepCount", stepCount);
        _propBlock.SetInt("_MaxSteps", maxSteps);
        _propBlock.SetFloat("_TransparencyThreshold", transparencyThreshold);

        // 应用PropertyBlock到Renderer
        _renderer.SetPropertyBlock(_propBlock);
    }
} 