//
//  GalleryPageController.swift
//  TelegramMac
//
//  Created by keepcoder on 14/12/2016.
//  Copyright © 2016 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import SwiftSignalKitMac
import AVFoundation


fileprivate extension MagnifyView {
    var minX:CGFloat {
        if contentView.frame.minX > 0 {
            return frame.minX + contentView.frame.minX
        }
        return frame.minX
    }
}

class GalleryPageView : NSView {
    fileprivate var lockedInteractions:Bool = false
    init() {
        super.init(frame:NSZeroRect)
        self.wantsLayer = true
    }

    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

class GalleryPageController : NSObject, NSPageControllerDelegate {

    private let controller:NSPageController = NSPageController()
    private let ioDisposabe:MetaDisposable = MetaDisposable()
    private var identifiers:[NSPageController.ObjectIdentifier:MGalleryItem] = [:]
    private var cache:NSCache<AnyObject, NSViewController> = NSCache()
    private var queuedTransitions:[UpdateTransition<MGalleryItem>] = []
    let contentInset:NSEdgeInsets
    private(set) var lockedTransition:Bool = false {
        didSet {
            view.lockedInteractions = lockedTransition
            if !lockedTransition {
                _ = enqueueTransitions()
            }
        }
    }
    private var startIndex:Int = -1
    let view:GalleryPageView = GalleryPageView()
    private let captionView: TextView = TextView()
    private let window:Window
    let selectedIndex:ValuePromise<Int> = ValuePromise(ignoreRepeated: false)
    init(frame:NSRect, contentInset:NSEdgeInsets, interactions:GalleryInteractions, window:Window) {
        self.contentInset = contentInset
        self.window = window
        
        super.init()
        cache.countLimit = 10
        
        window.set(mouseHandler: { [weak self] (_) -> KeyHandlerResult in
            if let view = self?.controller.selectedViewController?.view as? MagnifyView, let window = view.window {
                
                let point = window.mouseLocationOutsideOfEventStream                
                if point.x < view.minX && !view.mouseInContent && view.magnify == 1.0 {
                    _ = interactions.previous()
                } else if view.mouseInContent && view.magnify == 1.0 {
                    _ = interactions.next()
                } else {
                    let hitTestView = window.contentView?.hitTest(point)
                    if hitTestView is GalleryBackgroundView || view.contentView == hitTestView?.subviews.first {
                        _ = interactions.dismiss()

                    } else {
                        return .invokeNext
                    }
                }
                
            }
            return .invoked
        }, with: self, for: .leftMouseUp)
        
        
        window.set(mouseHandler: { [weak self] (_) -> KeyHandlerResult in
            if let strongSelf = self {
                if strongSelf.lockedTransition {
                    return .invoked
                } else {
                    return .invokeNext
                }
            }
            return .invoked
        }, with: self, for: .scrollWheel)
        
        
        window.set(mouseHandler: { [weak self] (_) -> KeyHandlerResult in
            if let view = self?.controller.selectedViewController?.view as? MagnifyView, let window = view.window {
                
                let point = window.mouseLocationOutsideOfEventStream
                let hitTestView = window.contentView?.hitTest(point)
                if view.contentView == hitTestView {
                    if let event = NSApp.currentEvent, let menu = interactions.contextMenu() {
                        NSMenu.popUpContextMenu(menu, with: event, for: view)
                    }
                } else {
                    return .invokeNext
                }
                
            }
            return .invoked
        }, with: self, for: .rightMouseUp)
        
       // view.background = .blackTransparent
        controller.view = view
        controller.view.frame = frame
        controller.delegate = self
        controller.transitionStyle = .horizontalStrip
    }
    
    func merge(with transition:UpdateTransition<MGalleryItem>) -> Bool {
        queuedTransitions.append(transition)
        return enqueueTransitions()
    }
    
    var isFullScreen: Bool {
        if let view = controller.selectedViewController?.view as? MagnifyView {
            if view.contentView.frame.size == window.frame.size {
                return true
            }
        }
        return false
    }
    
    var itemView:NSView? {
        return (controller.selectedViewController?.view as? MagnifyView)?.contentView
    }
    
    func enqueueTransitions() -> Bool {
        if !lockedTransition {
            
            let wasInited = !controller.arrangedObjects.isEmpty
            let item: MGalleryItem? = !controller.arrangedObjects.isEmpty ? self.item(at: controller.selectedIndex) : nil
            
            
            var items:[MGalleryItem] = controller.arrangedObjects as! [MGalleryItem]
            while !queuedTransitions.isEmpty {
                let transition = queuedTransitions[0]
                
                let searchItem:(AnyHashable)->MGalleryItem? = { stableId in
                    for item in items {
                        if item.stableId == stableId {
                            return item
                        }
                    }
                    return nil
                }
                
                for rdx in transition.deleted.reversed() {
                    let item = items[rdx]
                    identifiers.removeValue(forKey: item.identifier)
                    items.remove(at: rdx)                    
                }
                for (idx,item) in transition.inserted {
                    let item = searchItem(item.stableId) ?? item
                    identifiers[item.identifier] = item
                    items.insert(item, at: idx)
                }
                for (idx,item) in transition.updated {
                    let item = searchItem(item.stableId) ?? item
                    identifiers[item.identifier] = item
                    items[idx] = item
                }
                
                queuedTransitions.removeFirst()
            }
            
            if items.count > 0 {
                controller.arrangedObjects = items

                if let item = item {
                    for i in 0 ..< items.count {
                        if item.identifier == items[i].identifier {
                            if controller.selectedIndex != i {
                                controller.selectedIndex = i
                            }
                            break
                        }
                    }
                }
                if wasInited {
                    items[controller.selectedIndex].request(immediately: false)
                }
            }
            return items.isEmpty
        }
        return false
    }
    
    func next() {
        if !lockedTransition {
            set(index: min(controller.selectedIndex + 1, controller.arrangedObjects.count - 1), animated: false)
        }
    }
    
    func prev() {
        if !lockedTransition {
            set(index: max(controller.selectedIndex - 1, 0), animated: false)
        }
    }
    
    func zoomIn() {
        if let magnigy = controller.selectedViewController?.view as? MagnifyView {
            magnigy.zoomIn()
        }
    }
    
    func zoomOut() {
        if let magnigy = controller.selectedViewController?.view as? MagnifyView {
            magnigy.zoomOut()
        }
    }
    
    func set(index:Int, animated:Bool) {
        
        _ = enqueueTransitions()
        
        if queuedTransitions.isEmpty {
            let controller = self.controller
            let index = min(max(0,index),controller.arrangedObjects.count - 1)
            
            if animated {
                NSAnimationContext.runAnimationGroup({ (context) in
                    controller.animator().selectedIndex = index
                }) {
                    self.pageControllerDidEndLiveTransition(controller)
                }
            } else {
                if controller.selectedIndex != index {
                    controller.selectedIndex = index
                }
                pageControllerDidEndLiveTransition(controller, force:true)
                currentController = controller.selectedViewController
            }
        } 
    }
    

    func pageController(_ pageController: NSPageController, prepare viewController: NSViewController, with object: Any?) {
        if let object = object, let view = viewController.view as? MagnifyView {
            let item = self.item(for: object)
            view.contentSize = item.sizeValue
            view.minMagnify = item.minMagnify
            view.maxMagnify = item.maxMagnify
            
            
            item.view.set(.single(view.contentView))
            item.size.set(view.smartUpdater.get())
        }
    }
    
    
    func pageControllerWillStartLiveTransition(_ pageController: NSPageController) {
        lockedTransition = true
        startIndex = pageController.selectedIndex
    }
    
    func pageControllerDidEndLiveTransition(_ pageController: NSPageController, force:Bool) {
        let previousView = currentController?.view as? MagnifyView
        if startIndex != pageController.selectedIndex {
            if startIndex > 0 && startIndex < pageController.arrangedObjects.count {
                self.item(at: startIndex).disappear(for: previousView?.contentView)
            }
            startIndex = pageController.selectedIndex
            
           
//            if let caption = item.caption {
//                caption.measure(width: item.sizeValue.width)
//                captionView.update(caption)
//                captionView.setFrameSize(captionView.frame.size.width + 10, captionView.frame.size.height + 8)
//                (pageController.selectedViewController?.view as? MagnifyView)?.contentView.addSubview(captionView)
//                captionView.centerX(y: 10)
//            } else {
//                captionView.removeFromSuperview()
//            }
//            
            pageController.completeTransition()
            if  let controllerView = pageController.selectedViewController?.view as? MagnifyView, previousView != controllerView || force {
                let item = self.item(at: startIndex)
                item.appear(for: controllerView.contentView)
                controllerView.frame = view.focus(contentFrame.size, inset:contentInset)
            }
            
            
        }
    }
    
    private var currentController:NSViewController?
    
    func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
        pageControllerDidEndLiveTransition(pageController, force:false)
        currentController = pageController.selectedViewController
        if let view = pageController.view as? MagnifyView {
            window.makeFirstResponder(view.contentView)
        }
        lockedTransition = false
    }
    
    func pageController(_ pageController: NSPageController, didTransitionTo object: Any) {
        if pageController.selectedIndex >= 0 && pageController.selectedIndex < pageController.arrangedObjects.count {
            selectedIndex.set(pageController.selectedIndex)
        }
    }
    


    func pageController(_ pageController: NSPageController, identifierFor object: Any) -> NSPageController.ObjectIdentifier {
        return item(for: object).identifier
    }
    
    
    var contentFrame:NSRect {
        return NSMakeRect(frame.minX + contentInset.left, frame.minY + contentInset.top, frame.width - contentInset.left - contentInset.right, frame.height - contentInset.top - contentInset.bottom)
    }
    
    func pageController(_ pageController: NSPageController, frameFor object: Any?) -> NSRect {
        if let object = object {
            let item = self.item(for: object)
            let size = item.sizeValue

            return view.focus(size.fitted(contentFrame.size), inset:contentInset)
        }
        return view.bounds
    }
    
    func pageController(_ pageController: NSPageController, viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier) -> NSViewController {
        if let controller = cache.object(forKey: identifier as AnyObject)   {
            return controller
        } else {
            let controller = NSViewController()
            let item = identifiers[identifier]!
            let view = item.singleView()
            view.wantsLayer = true
            view.background = theme.colors.background
            controller.view = MagnifyView(view, contentSize:item.sizeValue)
            cache.setObject(controller, forKey: identifier as AnyObject)
            item.request()
            return controller
        }
    }
    
    
    var frame:NSRect {
        return view.frame
    }
    
    var count: Int {
        return controller.arrangedObjects.count
    }
    
    func item(for object:Any) -> MGalleryItem {
        return object as! MGalleryItem
    }
    
    func index(for item:MGalleryItem) -> Int? {
        for i in 0 ..< controller.arrangedObjects.count {
            if let _item = controller.arrangedObjects[i] as? MGalleryItem {
                if _item.stableId == item.stableId {
                    return i
                }
            }
        }
        return nil
    }
    
    func item(at index:Int) -> MGalleryItem {
        return controller.arrangedObjects[index] as! MGalleryItem
    }
    
    var selectedItem:MGalleryItem? {
        if controller.arrangedObjects.count > 0 {
            return controller.arrangedObjects[controller.selectedIndex] as? MGalleryItem
        }
        return nil
    }
    
    func animateIn( from:@escaping(AnyHashable)->NSView?, completion:(()->Void)? = nil) ->Void {
        if let selectedView = controller.selectedViewController?.view as? MagnifyView, let item = self.selectedItem {
            lockedTransition = true
            if let oldView = from(item.stableId), let oldWindow = oldView.window {
                selectedView.isHidden = true
                
                ioDisposabe.set((item.image.get() |> take(1)).start(next: { [weak self, weak selectedView] image in
                    
                    if let view = self?.view, let contentInset = self?.contentInset, let contentFrame = self?.contentFrame {
                        let newRect = view.focus(item.sizeValue.fitted(contentFrame.size), inset:contentInset)
                        let oldRect = oldWindow.convertToScreen(oldView.convert(oldView.bounds, to: nil))
                        
                        selectedView?.contentSize = item.sizeValue.fitted(contentFrame.size)
                        
                        if let _ = image, let strongSelf = self {
                            self?.animate(oldRect: oldRect, newRect: newRect, newAlphaFrom: 0, newAlphaTo:1, oldAlphaFrom: 1, oldAlphaTo:0, contents: image, oldView: oldView, completion: { [weak strongSelf] in
                                selectedView?.isHidden = false
                                strongSelf?.lockedTransition = false
                            })
                        } else {
                            selectedView?.isHidden = false
                            self?.lockedTransition = false
                        }
                    }
                    
                    
                    completion?()

                }))
            } else {
                ioDisposabe.set((item.image.get() |> take(1)).start(next: { [weak self] image in
                    //selectedView?.isHidden = false
                    self?.lockedTransition = false
                    if let completion = completion {
                        completion()
                    }
                }))
            }
        }
    }
    
    func animate(oldRect:NSRect, newRect:NSRect, newAlphaFrom:CGFloat, newAlphaTo:CGFloat, oldAlphaFrom:CGFloat, oldAlphaTo:CGFloat, contents:CGImage?, oldView:NSView, completion:@escaping ()->Void) {
        
        lockedTransition = true
        
        
        let view = self.view
        
        let newView:NSView = NSView(frame: oldRect)
        newView.wantsLayer = true
        newView.layer?.opacity = Float(newAlphaFrom)
        newView.layer?.contents = contents
        newView.layer?.backgroundColor = theme.colors.background.cgColor
        
        let copyView = oldView.copy() as! NSView
        copyView.layer?.backgroundColor = theme.colors.background.cgColor
        copyView.frame = oldRect
        copyView.wantsLayer = true
        copyView.layer?.opacity = Float(oldAlphaFrom)
        view.addSubview(newView)
        view.addSubview(copyView)
        
        CATransaction.begin()
        
        let duration:Double = 0.2
        
        newView._change(pos: newRect.origin, animated: true, duration: duration, timingFunction: kCAMediaTimingFunctionSpring)
        newView._change(size: newRect.size, animated: true, duration: duration, timingFunction: kCAMediaTimingFunctionSpring)
        newView._change(opacity: newAlphaTo, duration: duration, timingFunction: kCAMediaTimingFunctionSpring)
        
        copyView._change(pos: newRect.origin, animated: true, duration: duration, timingFunction: kCAMediaTimingFunctionSpring)
        copyView._change(size: newRect.size, animated: true, duration: duration, timingFunction: kCAMediaTimingFunctionSpring)
        copyView._change(opacity: oldAlphaTo, duration: duration, timingFunction: kCAMediaTimingFunctionSpring) { [weak self] _ in
            completion()
            self?.lockedTransition = false
            if let strongSelf = self {
                newView.removeFromSuperview()
                copyView.removeFromSuperview()
                Queue.mainQueue().after(0.1, { [weak strongSelf] in
                    if let view = strongSelf?.controller.selectedViewController?.view as? MagnifyView {
                        strongSelf?.window.makeFirstResponder(view)
                    }
                })
            }
        }
        CATransaction.commit()


    }
    
    func animateOut( to:@escaping(AnyHashable)->NSView?, completion:(()->Void)? = nil) ->Void {
        
        lockedTransition = true
        if let selectedView = controller.selectedViewController?.view as? MagnifyView, let item = selectedItem {
            selectedView.isHidden = true
            item.disappear(for: selectedView.contentView)
            if let oldView = to(item.stableId), let window = oldView.window {
                let newRect = window.convertToScreen(oldView.convert(oldView.bounds, to: nil))
                let oldRect = view.focus(item.sizeValue.fitted(contentFrame.size), inset:contentInset)
                
                ioDisposabe.set((item.image.get() |> take(1)).start(next: { [weak self] (image) in
                    self?.animate(oldRect: oldRect, newRect: newRect, newAlphaFrom: 1, newAlphaTo:0, oldAlphaFrom: 0, oldAlphaTo: 1, contents: image, oldView: oldView, completion: {
                        completion?()
                    })

                }))

            } else {
                view._change(opacity: 0, completion: { (_) in
                    completion?()
                })
            }
        } else {
            view._change(opacity: 0, completion: { (_) in
                completion?()
            })
        }
    }
    
    deinit {
        window.remove(object: self, for: .leftMouseUp)
        ioDisposabe.dispose()
    }

}

