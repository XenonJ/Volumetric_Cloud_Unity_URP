using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
#endif

[ExecuteAlways]
public class WorleyNoiseGenerator3D : MonoBehaviour
{
    [Header("Compute Shader 设置")]
    public ComputeShader worleyComputeShader;
    
    [Header("纹理尺寸")]
    public int textureWidth = 64;
    public int textureHeight = 64;
    public int textureDepth = 64;
    
    [Header("Worley Noise 参数")]
    public float cellSize = 8.0f;
    public float seed = 0.0f;
    
    [Header("切片预览材质（使用下面给出的 Slice3DShader）")]
    public Material sliceMaterial;
    
    [Header("预览与更新控制")]
    [Tooltip("是否显示右上角的切片预览")]
    public bool displayPreview = true;
    [Tooltip("参数变化时自动重新生成纹理")]
    public bool autoRecompute = true;

    [Header("使用该噪声纹理的材质")]
    [Tooltip("将此 3D 纹理赋给材质的 _VolumeTex 属性")]
    public Material volumeMaterial;
    
    // 内部生成的 3D 渲染纹理
    private RenderTexture volumeTexture;

    void OnEnable()
    {
        GenerateTexture();
        if (volumeMaterial != null)
        {
            volumeMaterial.SetTexture("_VolumeTex", volumeTexture);
        }
    }

    // 当在编辑器中调整参数时自动调用（仅在 autoRecompute 为 true 时）
    void OnValidate()
    {
        if (autoRecompute)
        {
            GenerateTexture();
            if (volumeMaterial != null)
            {
                volumeMaterial.SetTexture("_VolumeTex", volumeTexture);
            }
        }
    }

    /// <summary>
    /// 手动调用此方法重新生成 3D 纹理
    /// </summary>
    public void GenerateTexture()
    {
        if (worleyComputeShader == null)
        {
            Debug.LogWarning("请在 Inspector 中指定 Compute Shader！");
            return;
        }
        
        // 如果已有纹理，则释放资源
        if (volumeTexture != null)
        {
            volumeTexture.Release();
            volumeTexture = null;
        }
        
        // 创建 3D RenderTexture
        volumeTexture = new RenderTexture(textureWidth, textureHeight, 0, RenderTextureFormat.ARGBFloat);
        volumeTexture.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
        volumeTexture.volumeDepth = textureDepth;
        volumeTexture.enableRandomWrite = true;
        volumeTexture.wrapMode = TextureWrapMode.Repeat;
        volumeTexture.filterMode = FilterMode.Bilinear;
        volumeTexture.Create();
        
        // 设置 compute shader 参数
        int kernelHandle = worleyComputeShader.FindKernel("CSMain");
        worleyComputeShader.SetInt("textureWidth", textureWidth);
        worleyComputeShader.SetInt("textureHeight", textureHeight);
        worleyComputeShader.SetInt("textureDepth", textureDepth);
        worleyComputeShader.SetFloat("cellSize", cellSize);
        worleyComputeShader.SetFloat("seed", seed);
        worleyComputeShader.SetTexture(kernelHandle, "Result", volumeTexture);
        
        // Dispatch 计算（注意：不要在 Update 中持续调用）
        int threadGroupsX = Mathf.CeilToInt(textureWidth / 8.0f);
        int threadGroupsY = Mathf.CeilToInt(textureHeight / 8.0f);
        int threadGroupsZ = Mathf.CeilToInt(textureDepth / 8.0f);
        worleyComputeShader.Dispatch(kernelHandle, threadGroupsX, threadGroupsY, threadGroupsZ);
    }

    // 在屏幕右上角绘制 3x3 的切片预览（仅当 displayPreview 为 true 时）
    void OnGUI()
    {
        if (!displayPreview)
            return;

        if (volumeTexture == null || sliceMaterial == null)
            return;
        
        // 将生成的 3D 纹理赋给材质
        sliceMaterial.SetTexture("_VolumeTex", volumeTexture);
        
        int gridRows = 3;
        int gridCols = 3;
        int cellSizePx = 100; // 每个预览单元的尺寸（像素）
        int margin = 10;       // 单元间隔
        
        // 计算整个预览网格的尺寸及起始位置（右上角）
        float gridWidth = gridCols * cellSizePx + (gridCols - 1) * margin;
        float gridHeight = gridRows * cellSizePx + (gridRows - 1) * margin;
        float startX = Screen.width - gridWidth - margin;
        float startY = margin;
        
        // 取 9 个均匀分布的切片（_Slice 范围 [0,1]）
        int totalSlices = gridRows * gridCols;
        for (int row = 0; row < gridRows; row++)
        {
            for (int col = 0; col < gridCols; col++)
            {
                int sliceIndex = row * gridCols + col;
                float sliceCoord = (sliceIndex + 0.5f) / totalSlices;
                sliceMaterial.SetFloat("_Slice", sliceCoord);
                
                // 每个切片在屏幕上的位置
                float x = startX + col * (cellSizePx + margin);
                float y = startY + row * (cellSizePx + margin);
                Rect rect = new Rect(x, y, cellSizePx, cellSizePx);
                Graphics.DrawTexture(rect, volumeTexture, sliceMaterial);
            }
        }
    }

    // 确保在脚本禁用时释放 GPU 资源
    void OnDisable()
    {
        if (volumeTexture != null)
        {
            volumeTexture.Release();
            volumeTexture = null;
        }
    }
}