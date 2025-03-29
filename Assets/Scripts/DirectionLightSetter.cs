using System;
using UnityEngine;

public class RotatingDirectionalLight : MonoBehaviour
{
    // 旋转速度，单位为度/秒
    public float rotationSpeed = 10f;
    // 旋转轴（例如绕 Y 轴旋转）
    public Vector3 rotationAxis = Vector3.up;
    // 旋转中心（此处为原点）
    public Vector3 centerPoint = Vector3.zero;
    public Material targetMaterial;

    void FixedUpdate()
    {
        // 绕中心点旋转
        transform.RotateAround(centerPoint, rotationAxis, rotationSpeed * Time.deltaTime);
        // 始终使光源指向中心点
        transform.LookAt(centerPoint);
        
        // 获取当前光源的方向（一般来说，Directional Light 的方向与 transform.forward 相同，
        // 但有时你可能需要使用 -transform.forward，根据你 shader 中的实现来选择）
        Vector3 lightDirection = transform.forward;
        
        targetMaterial.SetVector("_LightDir", lightDirection);
    }

    void OnValidate()
    {
        // 在编辑器中实时更新材质属性
        if (targetMaterial != null)
        {
            Vector3 lightDirection = transform.forward;
            targetMaterial.SetVector("_LightDir", lightDirection);
        }
    }
}
