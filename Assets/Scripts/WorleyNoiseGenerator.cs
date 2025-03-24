using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
#endif

[ExecuteAlways]
public class WorleyNoiseGenerator : MonoBehaviour
{
    public ComputeShader computeShader;
    public int textureWidth = 256;
    public int textureHeight = 256;
    public float cellSize = 8.0f;
    public float seed = 0.0f;

    private RenderTexture noiseTexture;

    void Start()
    {
        GenerateTexture();
    }

    // 当 Inspector 中的属性发生改变时调用
    void OnValidate()
    {
        // 如果在编辑器非播放状态下也想实时更新
        if (!Application.isPlaying)
        {
#if UNITY_EDITOR
            // 使用 delayCall 防止 OnValidate 重复调用导致问题
            EditorApplication.delayCall += () => { if (this != null) GenerateTexture(); };
#endif
        }
        else
        {
            GenerateTexture();
        }
    }

    public void GenerateTexture()
    {
        // 如果已有 RenderTexture，先释放它
        if (noiseTexture != null)
        {
            noiseTexture.Release();
        }

        // 创建新的 RenderTexture 并启用随机写入
        noiseTexture = new RenderTexture(textureWidth, textureHeight, 0, RenderTextureFormat.ARGBFloat);
        noiseTexture.enableRandomWrite = true;
        noiseTexture.Create();

        // 获取 Compute Shader 中 kernel 的句柄
        int kernelHandle = computeShader.FindKernel("CSMain");

        // 传递参数到 Compute Shader
        computeShader.SetInt("textureWidth", textureWidth);
        computeShader.SetInt("textureHeight", textureHeight);
        computeShader.SetFloat("cellSize", cellSize);
        computeShader.SetFloat("seed", seed);
        computeShader.SetTexture(kernelHandle, "Result", noiseTexture);

        // 根据线程组大小（8x8）计算 Dispatch 的组数
        int threadGroupsX = Mathf.CeilToInt(textureWidth / 8.0f);
        int threadGroupsY = Mathf.CeilToInt(textureHeight / 8.0f);

        // 执行 Compute Shader
        computeShader.Dispatch(kernelHandle, threadGroupsX, threadGroupsY, 1);

        // 如果当前物体有 Renderer，则更新材质的纹理
        Renderer rend = GetComponent<Renderer>();
        if (rend != null)
        {
            rend.material.mainTexture = noiseTexture;
        }
    }

    // 用 OnGUI 显示纹理在屏幕左上角（可选）
    void OnGUI()
    {
        if (noiseTexture != null)
        {
            GUI.DrawTexture(new Rect(0, 0, textureWidth, textureHeight), noiseTexture, ScaleMode.ScaleToFit, false);
        }
    }

    // 保存纹理到文件（可以通过 Inspector 按钮调用）
    [ContextMenu("Save Texture To File")]
    public void SaveTextureToFile()
    {
        RenderTexture currentRT = RenderTexture.active;
        RenderTexture.active = noiseTexture;

        Texture2D tex = new Texture2D(noiseTexture.width, noiseTexture.height, TextureFormat.RGBAFloat, false);
        tex.ReadPixels(new Rect(0, 0, noiseTexture.width, noiseTexture.height), 0, 0);
        tex.Apply();

        RenderTexture.active = currentRT;

        byte[] bytes = tex.EncodeToPNG();
        string filePath = Application.dataPath + "/Textures/WorleyNoise.png";
        System.IO.File.WriteAllBytes(filePath, bytes);

        Debug.Log("Texture saved to " + filePath);
    }
}