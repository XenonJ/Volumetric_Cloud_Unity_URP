using UnityEngine;

public class RayMarchingCloud_BoxSetter : MonoBehaviour
{
    private Renderer _renderer;
    private MaterialPropertyBlock _propBlock;

    private int frameCounter = 0;

    void Awake()
    {
        _renderer = GetComponent<Renderer>();
        _propBlock = new MaterialPropertyBlock();
    }

    void Start()
    {
        SetBoxProperties();
    }

    void Update()
    {
        // 每帧更新_BoxMin和_BoxMax
        SetBoxProperties();
        frameCounter++;
        SetFrameCounter();
    }

    // 也可以在Editor里实时更新（便于调试）
    void OnValidate()
    {
        if (_renderer == null)
            _renderer = GetComponent<Renderer>();

        if (_propBlock == null)
            _propBlock = new MaterialPropertyBlock();

        SetBoxProperties();
    }

    void SetBoxProperties()
    {
        // 获取当前Renderer的PropertyBlock（如果已有）
        _renderer.GetPropertyBlock(_propBlock);

        // 单独修改这个Renderer的_BoxMin和_BoxMax
        _propBlock.SetVector("_BoxMin", transform.position - transform.localScale / 2);
        _propBlock.SetVector("_BoxMax", transform.position + transform.localScale / 2);

        // 应用PropertyBlock到Renderer
        _renderer.SetPropertyBlock(_propBlock);
    }

    void SetFrameCounter()
    {
        _renderer.GetPropertyBlock(_propBlock);
        _propBlock.SetInt("_FrameCounter", frameCounter);
        _renderer.SetPropertyBlock(_propBlock);
    }
}
