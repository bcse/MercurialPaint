//
//  ViewController.swift
//  MercurialPaint
//
//  Created by Simon Gladman on 04/12/2015.
//  Copyright © 2015 Simon Gladman. All rights reserved.
//

import UIKit

class ViewController: UIViewController
{

    let mercurialPaint = MercurialPaint(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    let shadingImageEditor = ShadingImageEditor()
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        view.backgroundColor = .black
       
        view.addSubview(mercurialPaint)
        view.addSubview(shadingImageEditor)
        
        shadingImageEditor.addTarget(self,
                                     action: #selector(shadingImageChange),
                                     for: .valueChanged)
    }

    @objc func shadingImageChange()
    {
        mercurialPaint.shadingImage = shadingImageEditor.image
    }
    
    override func viewDidLayoutSubviews()
    {
        mercurialPaint.frame = CGRect(x: 0,
            y: 0,
            width: 1024,
            height: 1024)
        
        shadingImageEditor.frame = CGRect(x: 1026,
            y: 0,
            width: view.frame.width - 1026,
            height: view.frame.height)
    }
    
    override var prefersStatusBarHidden: Bool {
        get { return true }
    }
}

