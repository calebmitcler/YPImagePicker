//
//  YPImagePicker.swift
//  YPImgePicker
//
//  Created by Sacha Durand Saint Omer on 27/10/16.
//  Copyright © 2016 Yummypets. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

public protocol YPImagePickerDelegate: AnyObject {
    func noPhotos()
    func shouldAddToSelection(indexPath: IndexPath, numSelections: Int) -> Bool
}

open class YPImagePicker: UINavigationController {
      
    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    public var _didFinishPicking: (([YPMediaItem], CGRect?, String?, Bool) -> Void)?
    public func didFinishPicking(completion: @escaping (_ items: [YPMediaItem], _ cropRect: CGRect?, _ assetId: String?, _ cancelled: Bool) -> Void) {
        _didFinishPicking = completion
    }
    public weak var imagePickerDelegate: YPImagePickerDelegate?
    
    open override var preferredStatusBarStyle: UIStatusBarStyle {
        return YPImagePickerConfiguration.shared.preferredStatusBarStyle
    }
    
    // This nifty little trick enables us to call the single version of the callbacks.
    // This keeps the backwards compatibility keeps the api as simple as possible.
    // Multiple selection becomes available as an opt-in.
    public func didSelect(items: [YPMediaItem], cropRect: CGRect?, assetId: String?) {
        _didFinishPicking?(items, cropRect, assetId, false)
    }
    
    public let loadingView = YPLoadingView()
    public let picker: YPPickerVC!
    
    /// Get a YPImagePicker instance with the default configuration.
    public convenience init() {
        self.init(configuration: YPImagePickerConfiguration.shared)
    }
    
    /// Get a YPImagePicker with the specified configuration.
    public required init(configuration: YPImagePickerConfiguration) {
        YPImagePickerConfiguration.shared = configuration
        picker = YPPickerVC()
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen // Force .fullScreen as iOS 13 now shows modals as cards by default.
        picker.imagePickerDelegate = self
        navigationBar.tintColor = .ypLabel
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
override open func viewDidLoad() {
        super.viewDidLoad()
        picker.didClose = { [weak self] in
            self?._didFinishPicking?([], nil, nil, true)
        }
        viewControllers = [picker]
        setupLoadingView()
        navigationBar.isTranslucent = false

        picker.didSelectItems = { [weak self] items in
            // Use Fade transition instead of default push animation
            let transition = CATransition()
            transition.duration = 0.3
            transition.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
            transition.type = CATransitionType.fade
            self?.view.layer.add(transition, forKey: nil)
            
            // Multiple items flow
            if items.count > 1 {
                if YPConfig.library.skipSelectionsGallery {
                    self?.didSelect(items: items, cropRect: nil, assetId: nil)
                    return
                } else {
                    let selectionsGalleryVC = YPSelectionsGalleryVC(items: items) { _, items in
                        self?.didSelect(items: items, cropRect: nil, assetId: nil)
                    }
                    self?.pushViewController(selectionsGalleryVC, animated: true)
                    return
                }
            }
            
            // One item flow
            let item = items.first!
            switch item {
            case .photo(let photo):
                let completion = { (photo: YPMediaPhoto, cropRect: CGRect?) in
                    let mediaItem = YPMediaItem.photo(p: photo)
                    // Save new image or existing but modified, to the photo album.
                    if YPConfig.shouldSaveNewPicturesToAlbum {
                        let isModified = photo.modifiedImage != nil
                        if photo.fromCamera || (!photo.fromCamera && isModified) {
                            YPPhotoSaver.trySaveImage(photo.image, inAlbumNamed: YPConfig.albumName)
                        }
                    }
                    self?.didSelect(items: [mediaItem], cropRect: cropRect, assetId: nil)
                }
                
                func showCropVC(photo: YPMediaPhoto, completion: @escaping (_ aphoto: YPMediaPhoto, _ cropRect: CGRect?) -> Void) {
                    if case let YPCropType.rectangle(ratio) = YPConfig.showsCrop {
                        let cropVC = YPCropVC(image: photo.image, ratio: ratio)
                        cropVC.didFinishCropping = { croppedImage, cropRect in
                            photo.modifiedImage = croppedImage
                            completion(photo, cropRect)
                        }
                        self?.pushViewController(cropVC, animated: true)
                    } else {
                        completion(photo, nil)
                    }
                }
                
                if YPConfig.showsPhotoFilters {
                    let filterVC = YPPhotoFiltersVC(inputPhoto: photo,
                                                    isFromSelectionVC: false)
                    // Show filters and then crop
                    filterVC.didSave = { outputMedia in
                        if case let YPMediaItem.photo(outputPhoto) = outputMedia {
                            showCropVC(photo: outputPhoto, completion: completion)
                        }
                    }
                    self?.pushViewController(filterVC, animated: false)
                } else {
                    showCropVC(photo: photo, completion: completion)
                }
            case .video(let video):
                var crop: CGRect?
                var phassetId: String?
                func showCropVC(video: YPMediaVideo, completion: @escaping (_ aphoto: YPMediaVideo) -> Void) {
                    phassetId = video.asset?.localIdentifier ?? ""
                    if case let YPCropType.rectangle(ratio) = YPConfig.showsCrop {
                        let cropVC = YPCropVC(video: video, ratio: ratio)
                        
                        cropVC.didFinishVideoCropping = { croppedVideo, cropRect in
                            crop = cropRect
                            completion(croppedVideo)
                        }
                        self?.pushViewController(cropVC, animated: true)
                    } else {
                        completion(video)
                    }
                }
                
                let completion = { (croppedVideo: YPMediaVideo) in
                    if YPConfig.showsVideoTrimmer {
                        let videoFiltersVC = YPVideoFiltersVC.initWith(video: croppedVideo,
                                                                       isFromSelectionVC: false)
                        videoFiltersVC.didSave = { [weak self] outputMedia in
                            self?.didSelect(items: [outputMedia], cropRect: crop, assetId: phassetId)
                        }
                        self?.pushViewController(videoFiltersVC, animated: true)
                    } else {
                        self?.didSelect(items: [YPMediaItem.video(v: croppedVideo)], cropRect: crop, assetId: phassetId)
                    }
                }
                showCropVC(video: video, completion: completion)
            }
        }
    }
    
    deinit {
        print("Piclsker deinited 👍")
    }
    
    private func setupLoadingView() {
        view.sv(
            loadingView
        )
        loadingView.fillContainer()
        loadingView.alpha = 0
    }
}

extension YPImagePicker: ImagePickerDelegate {
    
    func noPhotos() {
        self.imagePickerDelegate?.noPhotos()
    }
    
    func shouldAddToSelection(indexPath: IndexPath, numSelections: Int) -> Bool {
        return self.imagePickerDelegate?.shouldAddToSelection(indexPath: indexPath, numSelections: numSelections)
            ?? true
    }
}


