//
//  FSPagerViewLayout.swift
//  FSPagerView
//
//  Created by Wenchao Ding on 20/12/2016.
//  Copyright © 2016 Wenchao Ding. All rights reserved.
//

import UIKit

class FSPagerViewLayout: UICollectionViewLayout {
    
    internal var contentSize: CGSize = .zero
    internal var leadingSpacing: CGFloat = 0
    internal var itemSpacing: CGFloat = 0
    internal var needsReprepare = true
    internal var scrollDirection: FSPagerView.ScrollDirection = .horizontal
    
    open override class var layoutAttributesClass: AnyClass {
        FSPagerViewLayoutAttributes.self
    }
    
    fileprivate var pagerView: FSPagerView? {
        collectionView?.superview?.superview as? FSPagerView
    }
    
    fileprivate var collectionViewSize: CGSize = .zero
    fileprivate var numberOfSections = 1
    fileprivate var numberOfItems = 0
    fileprivate var actualInteritemSpacing: CGFloat = 0
    fileprivate var actualItemSize: CGSize = .zero
    
    override init() {
        super.init()
        commonInit()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    
    deinit {
        #if !os(tvOS)
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        #endif
    }
    
    override open func prepare() {
        guard let collectionView, let pagerView else { return }
        guard needsReprepare || collectionViewSize != collectionView.frame.size else { return }
        needsReprepare = false
        
        collectionViewSize = collectionView.frame.size

        // Calculate basic parameters/variables
        numberOfSections = pagerView.numberOfSections(in: collectionView)
        numberOfItems = pagerView.collectionView(collectionView, numberOfItemsInSection: 0)
        actualItemSize = if pagerView.itemSize == .zero {
            collectionView.frame.size
        } else {
            pagerView.itemSize
        }

        actualInteritemSpacing = if let transformer = pagerView.transformer {
            transformer.proposedInteritemSpacing()
        } else {
            pagerView.interitemSpacing
        }

        scrollDirection = pagerView.scrollDirection
        leadingSpacing = scrollDirection == .horizontal ? (collectionView.frame.width-actualItemSize.width)*0.5 : (collectionView.frame.height-actualItemSize.height)*0.5
        itemSpacing = (scrollDirection == .horizontal ? actualItemSize.width : actualItemSize.height) + actualInteritemSpacing
        
        // Calculate and cache contentSize, rather than calculating each time
        self.contentSize = {
            let numberOfItems = numberOfItems * numberOfSections
            switch scrollDirection {
            case .horizontal:
                var contentSizeWidth = leadingSpacing * 2 // Leading & trailing spacing
                contentSizeWidth += CGFloat(numberOfItems-1) * actualInteritemSpacing // Interitem spacing
                contentSizeWidth += CGFloat(numberOfItems) * actualItemSize.width // Item sizes
                let contentSize = CGSize(width: contentSizeWidth, height: collectionView.frame.height)
                return contentSize
            case .vertical:
                var contentSizeHeight = leadingSpacing*2 // Leading & trailing spacing
                contentSizeHeight += CGFloat(numberOfItems - 1) * actualInteritemSpacing // Interitem spacing
                contentSizeHeight += CGFloat(numberOfItems) * actualItemSize.height // Item sizes
                let contentSize = CGSize(width: collectionView.frame.width, height: contentSizeHeight)
                return contentSize
            }
        }()
        self.adjustCollectionViewBounds()
    }
    
    override open var collectionViewContentSize: CGSize {
        self.contentSize
    }
    
    override open func shouldInvalidateLayout(
        forBoundsChange newBounds: CGRect
    ) -> Bool {
        true
    }
    
    override open func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var layoutAttributes: [UICollectionViewLayoutAttributes] = []
        guard itemSpacing > 0, !rect.isEmpty else { return layoutAttributes }
        let rect = rect.intersection(CGRect(origin: .zero, size: contentSize))
        guard !rect.isEmpty else { return layoutAttributes }
        // Calculate start position and index of certain rects
        let numberOfItemsBefore = switch scrollDirection {
        case .horizontal:
            max(Int((rect.minX - leadingSpacing) / itemSpacing), 0)
        case .vertical:
            max(Int((rect.minY - leadingSpacing) / itemSpacing), 0)
        }
        let startPosition = leadingSpacing + CGFloat(numberOfItemsBefore) * itemSpacing
        let startIndex = numberOfItemsBefore
        // Create layout attributes
        var itemIndex = startIndex
        
        var origin = startPosition
        let maxPosition = switch scrollDirection {
        case .horizontal:
            min(rect.maxX,contentSize.width - actualItemSize.width - leadingSpacing)
        case .vertical:
            min(rect.maxY,contentSize.height - actualItemSize.height - leadingSpacing)
        }
        // https://stackoverflow.com/a/10335601/2398107
        while origin-maxPosition <= max(CGFloat(100.0) * .ulpOfOne * abs(origin+maxPosition), .leastNonzeroMagnitude) {
            let indexPath = IndexPath(item: itemIndex % numberOfItems, section: itemIndex / numberOfItems)
            let attributes = layoutAttributesForItem(at: indexPath) as! FSPagerViewLayoutAttributes
            applyTransform(to: attributes, with: pagerView?.transformer)
            layoutAttributes.append(attributes)
            itemIndex += 1
            origin += itemSpacing
        }
        return layoutAttributes
        
    }
    
    override open func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = FSPagerViewLayoutAttributes(forCellWith: indexPath)
        attributes.indexPath = indexPath
        let frame = frame(for: indexPath)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        attributes.center = center
        attributes.size = actualItemSize
        return attributes
    }
    
    override open func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        guard let collectionView, let pagerView else { return proposedContentOffset }

        var proposedContentOffset = proposedContentOffset
        
        func calculateTargetOffset(by proposedOffset: CGFloat, boundedOffset: CGFloat) -> CGFloat {
            var targetOffset = if pagerView.decelerationDistance == FSPagerView.automaticDistance {
                if abs(velocity.x) >= 0.3 {
                    round(proposedOffset / itemSpacing + 0.35 * velocity.x >= 0 ? 1.0 : -1.0) * itemSpacing // Ceil by 0.15, rather than 0.5
                } else {
                    round(proposedOffset / itemSpacing) * itemSpacing
                }
            } else {
                switch velocity.x {
                case 0.3 ... CGFloat.greatestFiniteMagnitude:
                    ceil(collectionView.contentOffset.x / itemSpacing + CGFloat(max(pagerView.decelerationDistance - 1, 0))) * itemSpacing
                case -CGFloat.greatestFiniteMagnitude ... -0.3:
                    floor(collectionView.contentOffset.x / itemSpacing - CGFloat(max(pagerView.decelerationDistance - 1, 0))) * itemSpacing
                default:
                    round(proposedOffset / itemSpacing) * itemSpacing
                }
            }
            targetOffset = max(0, targetOffset)
            targetOffset = min(boundedOffset, targetOffset)
            return targetOffset
        }
        let proposedContentOffsetX: CGFloat = switch scrollDirection {
        case .horizontal:
            calculateTargetOffset(
                by: proposedContentOffset.x, 
                boundedOffset: collectionView.contentSize.width - itemSpacing
            )
        case .vertical:
            proposedContentOffset.x
        }
        let proposedContentOffsetY = switch scrollDirection {
        case .horizontal:
            proposedContentOffset.y
        case .vertical:
            calculateTargetOffset(
                by: proposedContentOffset.y, 
                boundedOffset: collectionView.contentSize.height - itemSpacing
            )
        }
        proposedContentOffset = CGPoint(x: proposedContentOffsetX, y: proposedContentOffsetY)
        return proposedContentOffset
    }
    
    // MARK:- Internal functions
    
    internal func forceInvalidate() {
        needsReprepare = true
        invalidateLayout()
    }
    
    internal func contentOffset(for indexPath: IndexPath) -> CGPoint {
        let origin = frame(for: indexPath).origin
        
        guard let collectionView else { return origin }

        let contentOffsetX = switch scrollDirection {
        case .horizontal:
            origin.x - (collectionView.frame.width * 0.5 - actualItemSize.width * 0.5)
        case .vertical:
            CGFloat.zero
        }

        let contentOffsetY = switch scrollDirection {
        case .horizontal:
            CGFloat.zero
        case .vertical:
            origin.y - (collectionView.frame.height * 0.5 - actualItemSize.height * 0.5)
        }

        return CGPoint(x: contentOffsetX, y: contentOffsetY)
    }
    
    internal func frame(for indexPath: IndexPath) -> CGRect {
        guard let collectionView else { return .zero }

        let numberOfItems = numberOfItems * indexPath.section + indexPath.item

        let originX = switch scrollDirection {
        case .horizontal:
            leadingSpacing + CGFloat(numberOfItems) * itemSpacing
        case .vertical:
            (collectionView.frame.width - actualItemSize.width) * 0.5
        }

        let originY = switch scrollDirection {
        case .horizontal:
            (collectionView.frame.height - actualItemSize.height) * 0.5
        case .vertical:
            leadingSpacing + CGFloat(numberOfItems) * itemSpacing
        }

        let origin = CGPoint(x: originX, y: originY)
        let frame = CGRect(origin: origin, size: actualItemSize)
        return frame
    }
    
    // MARK:- Notification
    @objc
    fileprivate func didReceiveNotification(notification: Notification) {
        if pagerView?.itemSize == .zero {
            adjustCollectionViewBounds()
        }
    }
    
    // MARK:- Private functions
    
    fileprivate func commonInit() {
        #if !os(tvOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveNotification(notification:)),
            name: UIDevice.orientationDidChangeNotification, 
            object: nil
        )
        #endif
    }
    
    fileprivate func adjustCollectionViewBounds() {
        guard let collectionView, let pagerView else { return }
        let currentIndex = pagerView.currentIndex
        let newIndexPath = IndexPath(item: currentIndex, section: pagerView.isInfinite ? numberOfSections / 2 : 0)
        let contentOffset = self.contentOffset(for: newIndexPath)
        let newBounds = CGRect(origin: contentOffset, size: collectionView.frame.size)
        collectionView.bounds = newBounds
    }
    
    fileprivate func applyTransform(to attributes: FSPagerViewLayoutAttributes, with transformer: FSPagerViewTransformer?) {
        guard let collectionView, let transformer else { return }
        attributes.position = switch self.scrollDirection {
        case .horizontal:
            (attributes.center.x - collectionView.bounds.midX) / itemSpacing
        case .vertical:
            (attributes.center.y - collectionView.bounds.midY) / itemSpacing
        }
        attributes.zIndex = Int(numberOfItems)-Int(attributes.position)
        transformer.applyTransform(to: attributes)
    }
}
