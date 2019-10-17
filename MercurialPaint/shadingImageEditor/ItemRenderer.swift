//
//  LabelledSlider.swift
//  MercurialText
//
//  Created by Simon Gladman on 30/11/2015.
//  Copyright © 2015 Simon Gladman. All rights reserved.
//


import UIKit


class ItemRenderer: UITableViewCell
{
    let slider = LabelledSlider()
    
    var enabled: Bool = true
        {
        didSet
        {
            slider.isEnabled = enabled
        }
    }
    
    var parameter: Parameter?
        {
        didSet
        {
            slider.parameter = parameter
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?)
    {
        super.init(style: style, reuseIdentifier: "ItemRenderer")
        
        backgroundColor = .black
        
        contentView.addSubview(slider)
    }
    
    override func layoutSubviews()
    {
        slider.frame = bounds
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
}

// -------------------

class LabelledSlider: UIControl
{
    let label = UILabel()
    let valueLabel = UILabel()
    let slider = UISlider()
    
    override var isEnabled: Bool
    {
        didSet
        {
            isUserInteractionEnabled = isEnabled
            
            label.isEnabled = isEnabled
            valueLabel.isEnabled = isEnabled
            slider.isEnabled = isEnabled
        }
    }
    
    var parameter: Parameter?
    {
        didSet
        {
            guard let parameter = parameter else
            {
                label.text = ""
                return
            }
            
            label.text = parameter.name
            
            slider.minimumValue = parameter.minMax.min
            slider.maximumValue = parameter.minMax.max
            
            valueLabel.text = String(format: "%.2f", parameter.value)
            
            slider.value = Float(parameter.value)
        }
    }
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        label.textColor = .white
        valueLabel.textColor = .white
        
        label.adjustsFontSizeToFitWidth = true
        valueLabel.adjustsFontSizeToFitWidth = true
        
        valueLabel.textAlignment = .right
        
        addSubview(label)
        addSubview(valueLabel)
        addSubview(slider)
        
        label.numberOfLines = 0
        
        slider.addTarget(self, action: #selector(sliderChangeHandler), for: .valueChanged)
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func sliderChangeHandler()
    {
        parameter?.value = CGFloat(slider.value)
        
        guard let parameter = parameter else
        {
            return
        }
        
        valueLabel.text = String(format: "%.2f", parameter.value)
        
        sendActions(for: .valueChanged)
    }
    
    override func layoutSubviews()
    {
        label.frame = CGRect(x: 5,
            y: 2,
            width: frame.width / 2,
            height: label.intrinsicContentSize.height).insetBy(dx: 2, dy: 0)
        
        valueLabel.frame = CGRect(x: frame.width / 2,
            y: 2,
            width: frame.width / 2,
            height: valueLabel.intrinsicContentSize.height).insetBy(dx: 2, dy: 0)
        
        slider.frame = CGRect(x: 0,
            y: frame.height / 2 - 2,
            width: frame.width,
            height: slider.intrinsicContentSize.height).insetBy(dx: 2, dy: 0)
        
        layer.borderColor = UIColor.darkGray.cgColor
        layer.borderWidth = 1
    }
    
}
