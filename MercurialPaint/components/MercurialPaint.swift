//
//  MercurialPaint.swift
//  MercurialPaint
//
//  Created by Simon Gladman on 04/12/2015.
//  Copyright © 2015 Simon Gladman. All rights reserved.
//

import UIKit
import MetalKit
import MetalPerformanceShaders

let particleCount: Int = 2048

class MercurialPaint: UIView
{
    // MARK: Constants
    
    let device = MTLCreateSystemDefaultDevice()!
    let alignment:Int = 0x4000
    let particlesMemoryByteSize:Int = particleCount * MemoryLayout<Int>.size
    let halfPi = CGFloat.pi / 2
    
    let ciContext = CIContext(eaglContext: EAGLContext(api: .openGLES2)!, options: [CIContextOption.workingColorSpace: NSNull()])
    let heightMapFilter = CIFilter(name: "CIHeightFieldFromMask")!
    let shadedMaterialFilter = CIFilter(name: "CIShadedMaterial")!
    let maskToAlpha = CIFilter(name: "CIMaskToAlpha")!
    
    // MARK: Private variables
    
    private var threadsPerThreadgroup:MTLSize!
    private var threadgroupsPerGrid:MTLSize!
    
    private var particlesMemory: UnsafeMutableRawPointer? = nil
    private var particlesVoidPtr: OpaquePointer!
    private var particlesParticlePtr: UnsafeMutablePointer<Int>!
    private var particlesParticleBufferPtr: UnsafeMutableBufferPointer<Int>!
    
    private var particlesBufferNoCopy: MTLBuffer!
    private var touchLocations = [CGPoint](repeating: CGPoint(x: -1, y: -1), count: 4)
    private var touchForce:Float = 0
    
    private var pendingUpdate = false
    private var isBusy = false
    private var isDrawing = false
    {
        didSet
        {
            if isDrawing
            {
                metalView.isPaused = false
            }
        }
    }
   
    // MARK: Public
    
    var shadingImage: UIImage?
    {
        didSet
        {
            applyCoreImageFilter()
        }
    }
    
    // MARK: UI components
    
    var metalView: MTKView!
    let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024))
 
    // MARK: Lazy variables
    
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MTLPixelFormat.rgba8Unorm,
        width: 2048,
        height: 2048,
        mipmapped: false)
    
    lazy var paintingTexture: MTLTexture =
    {
        [unowned self] in

        self.textureDescriptor.usage = [.shaderRead, .shaderWrite]
        return self.device.makeTexture(descriptor: self.textureDescriptor)!
    }()
    
    lazy var intermediateTexture: MTLTexture =
    {
        [unowned self] in
        
        self.textureDescriptor.usage = [.shaderRead, .shaderWrite]
        return self.device.makeTexture(descriptor: self.textureDescriptor)!
        }()
    
    lazy var paintingShaderPipelineState: MTLComputePipelineState =
    {
       [unowned self] in
        
        do
        {
            let library = self.device.makeDefaultLibrary()!
            
            let kernelFunction = library.makeFunction(name: "mercurialPaintShader")
            let pipelineState = try self.device.makeComputePipelineState(function: kernelFunction!)
            
            return pipelineState
        }
        catch
        {
            fatalError("Unable to create censusTransformMonoPipelineState")
        }
    }()
    
    lazy var commandQueue: MTLCommandQueue =
    {
       [unowned self] in
        
        return self.device.makeCommandQueue()!
    }()
    
    lazy var blur: MPSImageGaussianBlur =
    {
        [unowned self] in
        
        return MPSImageGaussianBlur(device: self.device, sigma: 3)
        }()
    
    lazy var threshold: MPSImageThresholdBinary =
    {
        [unowned self] in
        
        return MPSImageThresholdBinary(device: self.device, thresholdValue: 0.5, maximumValue: 1, linearGrayColorTransform: nil)
    }()
    
    
    
    // MARK: Initialisation
    
    override init(frame frameRect: CGRect)
    {
        super.init(frame: frameRect)
        
        metalView = MTKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024), device: device)
        
        metalView.framebufferOnly = false
        metalView.colorPixelFormat = .bgra8Unorm
        
        metalView.delegate = self
        
        layer.borderColor = UIColor.white.cgColor
        layer.borderWidth = 1
   
        metalView.drawableSize = CGSize(width: 2048, height: 2048)
        
        addSubview(metalView)
        addSubview(imageView)
        
        setUpMetal()
        
        metalView.isPaused = true
    }

    required init(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setUpMetal()
    {
        posix_memalign(&particlesMemory, alignment, particlesMemoryByteSize)
        
        particlesVoidPtr = OpaquePointer(particlesMemory)
        particlesParticlePtr = UnsafeMutablePointer<Int>(particlesVoidPtr)
        particlesParticleBufferPtr = UnsafeMutableBufferPointer(start: particlesParticlePtr, count: particleCount)
        
        for index in particlesParticleBufferPtr.startIndex ..< particlesParticleBufferPtr.endIndex
        {
            particlesParticleBufferPtr[index] = Int(arc4random_uniform(9999))
        }
        
        let threadExecutionWidth = paintingShaderPipelineState.threadExecutionWidth
        
        threadsPerThreadgroup = MTLSize(width:threadExecutionWidth,height:1,depth:1)
        threadgroupsPerGrid = MTLSize(width:particleCount / threadExecutionWidth, height:1, depth:1)
        
        particlesBufferNoCopy = device.makeBuffer(bytesNoCopy: particlesMemory!,
            length: Int(particlesMemoryByteSize),
            options: .storageModeShared,
            deallocator: nil)
    }
    
    // MARK: Touch handlers
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        guard let touch = touches.first else
        {
            return
        }
        
        touchForce = touch.type == .stylus
            ? Float(touch.force / touch.maximumPossibleForce)
            : 0.5

        touchLocations = [touch.location(in: self)]
    
        isDrawing = true
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        guard let touch = touches.first, let coalescedTouches = event?.coalescedTouches(for: touch) else
        {
            return
        }

        touchForce = touch.type == .stylus
            ? Float(touch.force / touch.maximumPossibleForce)
            : 0.5
        
        touchLocations = coalescedTouches.map{ return $0.location(in: self) }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        touchLocations = [CGPoint](repeating: CGPoint(x: -1, y: -1), count: 4)
        
        applyCoreImageFilter()
        
        isDrawing = false
    }
    
    // MARK: Core Image Stuff
    
    func applyCoreImageFilter()
    {
        guard let drawable = metalView.currentDrawable else
        {
            print("currentDrawable returned nil")
            
            return
        }
        
        guard !isBusy else
        {
            pendingUpdate = true
            return
        }
        
        guard let shadingImage = shadingImage, let ciShadingImage = CIImage(image: shadingImage) else
        {
            return
        }
        
        isBusy = true
        
        let mercurialImage = CIImage(mtlTexture: drawable.texture, options: nil)
        
        DispatchQueue.global().async
        {
            let heightMapFilter = self.heightMapFilter.copy() as! CIFilter
            let shadedMaterialFilter = self.shadedMaterialFilter.copy() as! CIFilter
            let maskToAlpha = self.maskToAlpha.copy() as! CIFilter
            
            maskToAlpha.setValue(mercurialImage,
                forKey: kCIInputImageKey)
            
            heightMapFilter.setValue(maskToAlpha.value(forKey: kCIOutputImageKey),
                forKey: kCIInputImageKey)
            
            shadedMaterialFilter.setValue(heightMapFilter.value(forKey: kCIOutputImageKey),
                forKey: kCIInputImageKey)
            
            shadedMaterialFilter.setValue(ciShadingImage,
                forKey: "inputShadingImage")
            
            let filteredImageData = shadedMaterialFilter.value(forKey: kCIOutputImageKey) as! CIImage
            let filteredImageRef = self.ciContext.createCGImage(filteredImageData,
                                                                from: filteredImageData.extent)
            
            let finalImage = UIImage(cgImage: filteredImageRef!)
            
            DispatchQueue.main.async
            {
                self.imageView.image = finalImage
                self.isBusy = false
                
                if self.pendingUpdate
                {
                    self.pendingUpdate = false
                    
                    self.applyCoreImageFilter()
                }
            }
        }
    }
    
    func touchLocationsToVector(xy: XY) -> vector_int4
    {
        func getValue(point: CGPoint, xy: XY) -> Int32
        {
            switch xy
            {
            case .X:
                return Int32(point.x * 2)
            case .Y:
                return Int32(point.y * 2)
            }
        }
        
        let x = touchLocations.count > 0 ? getValue(point: touchLocations[0], xy: xy) : -1
        let y = touchLocations.count > 1 ? getValue(point: touchLocations[1], xy: xy) : -1
        let z = touchLocations.count > 2 ? getValue(point: touchLocations[2], xy: xy) : -1
        let w = touchLocations.count > 3 ? getValue(point: touchLocations[3], xy: xy) : -1
        
        let returnValue = vector_int4(x, y, z, w)
        
        return returnValue
    }

}

extension MercurialPaint: MTKViewDelegate
{
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    func draw(in view: MTKView)
    {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let commandEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        commandEncoder.setComputePipelineState(paintingShaderPipelineState)
        
        commandEncoder.setBuffer(particlesBufferNoCopy, offset: 0, index: 0)
    
        var xLocation = touchLocationsToVector(xy: .X)
        let xLocationBuffer = device.makeBuffer(bytes: &xLocation,
                                                length: MemoryLayout<vector_int4>.size,
                                                options: [])
        
        var yLocation = touchLocationsToVector(xy: .Y)
        let yLocationBuffer = device.makeBuffer(bytes: &yLocation,
                                                length: MemoryLayout<vector_int4>.size,
                                                options: [])
        
        let touchForceBuffer = device.makeBuffer(bytes: &touchForce,
                                                 length: MemoryLayout<Float>.size,
                                                 options: [])
        
        commandEncoder.setBuffer(xLocationBuffer, offset: 0, index: 1)
        commandEncoder.setBuffer(yLocationBuffer, offset: 0, index: 2)
        commandEncoder.setBuffer(touchForceBuffer, offset: 0, index: 3)
        
        commandEncoder.setTexture(paintingTexture, index: 0)
        
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        commandEncoder.endEncoding()
        
        guard let drawable = metalView.currentDrawable else
        {
            print("currentDrawable returned nil")
            
            return
        }
        
        blur.encode(commandBuffer: commandBuffer,
            sourceTexture: paintingTexture,
            destinationTexture: intermediateTexture)
        
        threshold.encode(commandBuffer: commandBuffer,
            sourceTexture: intermediateTexture,
            destinationTexture: drawable.texture)
        
        commandBuffer.commit()
        
        drawable.present()
 
        view.isPaused = !isDrawing
    }
}

enum XY
{
    case X, Y
}

