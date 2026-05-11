import SwiftUI
import CoreGraphics
import simd


extension CGPoint
{
	init(_ x:CGFloat,_ y:CGFloat)
	{
		self.init(x: x, y: y)
	}
}


extension CGPoint
{
	var simd : simd_float2	{	.init(Float(self.x),Float(self.y))	}
}

extension simd_float2
{
	var cgPoint : CGPoint	{	.init(x:CGFloat(x), y:CGFloat(y) )	}
}

struct CGLine
{
	var start : CGPoint
	var end : CGPoint
	var length : CGFloat		{	CGFloat(distance( start.simd, end.simd ))	}
	var middle : CGPoint		{	simd_mix( start.simd, end.simd, simd_float2(0.5,0.5) ).cgPoint	}
	var rotatedLeft90 : CGPoint	
	{
		let fwd = end.simd - start.simd
		let left = simd_float2.init( fwd.y, -fwd.x )
		return left.cgPoint
	}
	
	init(_ start: CGPoint,_ end: CGPoint) 
	{
		self.start = start
		self.end = end
	}
	
	//	returns null if this isnt long enough
	mutating func popStart(length:CGFloat) -> CGLine?
	{
		let length = Float(length)
		let dir = end.simd - start.simd
		let selfLength = simd.length(dir)
		if selfLength < length
		{
			return nil
		}
		let splitPoint = start.simd + normalize(dir) * length
		let popped = CGLine( start, splitPoint.cgPoint )
		self.start = splitPoint.cgPoint
		return popped
	}

}

protocol HasEdges
{
	var edges : [CGLine]	{get}
}


extension CGRect : HasEdges
{
	var edges: [CGLine] 
	{
		let topLeft = CGPoint(x:self.minX,y:self.minY)
		let topRight = CGPoint(x:self.maxX,y:self.minY)
		let bottomRight = CGPoint(x:self.maxX,y:self.maxY)
		let bottomLeft = CGPoint(x:self.minX,y:self.maxY)
		return [
			CGLine(topLeft,topRight),
			CGLine(topRight,bottomRight),
			CGLine(bottomRight,bottomLeft),
			CGLine(bottomLeft,topLeft)
		]
	}
}

internal struct ShapeError : Error
{
	var description : String
	
	init(_ description:String) 
	{
		self.description = description
	}
}

extension Collection where Element == CGLine
{
	var length : CGFloat
	{
		return self.reduce(0)
		{
			length,element in 
			return length + element.length
		}
	}
	
	func splitByLength(length:CGFloat) throws -> [CGLine]
	{
		//	avoid extra long loops
		let tinyLengthPx = Swift.max( 1.0, length * 0.10 )
		
		//	no infinite loops
		if length <= tinyLengthPx
		{
			throw ShapeError("Length (\(length)) must be more than \(tinyLengthPx)px")
		}
		
		var choppedLines : [CGLine] = []
		var remainder : CGLine?
		
		for line in self
		{
			//	skip tiny lines
			guard line.length >= tinyLengthPx else
			{
				continue
			}
			
			var line = line
			
			//	append remaining
			if let remainderLine = remainder
			{
				let require = length - remainderLine.length
				let suffix = line.popStart(length: require)
				//	if line isnt long enough... then swallow the whole line
				let newEnd = suffix ?? line
				let joined = CGLine( remainderLine.start, newEnd.end )
				
				//	we added to remainder
				remainder = nil
				choppedLines.append( joined )
				
				//	we used the whole of line
				if suffix == nil
				{
					continue
				}
			}
			
			//	avoid massive loops by requiring 1px long lines
			while remainder == nil && line.length > tinyLengthPx
			{
				let popped = line.popStart(length: length)
				guard let popped else
				{
					remainder = line
					break
				}
				
				choppedLines.append(popped)
			}
		}
		
		//	add remainder
		if let remainder, remainder.length >= tinyLengthPx 
		{
			choppedLines.append(remainder)
		}
		return choppedLines
	}
}
	

struct SpikyRectShape : Shape
{
	var cornerRadius : CGFloat = 30
	var step : CGFloat	{	spikeWidth	}
	var spikeHeight = CGFloat(20)
	var spikeWidth = CGFloat(30)
	
	func path(in rect: CGRect) -> Path 
	{
		//	clamp the spike height
		let minContentHeight = CGFloat(3)	//	this should be 2* strokeWidth
		let maxSpikeHeight = (rect.height / 2.0) - minContentHeight
		let spikeHeight = min( spikeHeight, maxSpikeHeight )
		
		let innerRect = rect.insetBy(dx: spikeHeight, dy: spikeHeight)
	
		let edges = innerRect.edges
		let permiterLength = edges.length
		
		//	need an odd number - and adjust width to then fit
		let spikeCount = floor(permiterLength / spikeWidth)
		let spikeWidth = permiterLength / CGFloat(spikeCount)
		let spikeBases = try? edges.splitByLength(length: spikeWidth)
		guard let spikeBases, let firstSpike = spikeBases.first else
		{
			return Path()
		}

		var path = Path()
		
		path.move(to: firstSpike.start)
		spikeBases.forEach
		{
			//	move here breaks paths
			//path.move(to: $0.start)
			let spikeOut = simd_normalize($0.rotatedLeft90.simd) * Float(spikeHeight)
			let spikeEnd = $0.middle.simd + spikeOut
			path.addLine(to: spikeEnd.cgPoint)
			path.addLine(to: $0.end)
		}
		path.closeSubpath()
		
		return path
	}
}

struct ContentView: View 
{
	@State var spikeWidth = CGFloat(30)
	@State var spikeHeight = CGFloat(30)
	@State var strokeWidth = CGFloat(4)
	@State var strokeColour = Color.black
	@State var fillColour = Color.pink
	
	var body: some View 
	{
		VStack
		{
			SpikyRectShape(spikeHeight: spikeHeight,spikeWidth: spikeWidth)
				.fill(fillColour)
				.stroke(strokeColour, lineWidth:strokeWidth)
				.padding(60)
			
			GroupBox("Params")
			{
				LabeledContent
				{
					Slider(value:$spikeWidth,in:0.1...100)
				}
			label:
				{
					Text("Spike Width \(spikeWidth)")
						.lineLimit(1)
						.frame(width: 120)
				}
				
				LabeledContent
				{
					Slider(value:$spikeHeight,in:-100...100)
				}
			label:
				{
					Text("Spike Height \(spikeHeight)")
						.lineLimit(1)
						.frame(width: 120)
				}
				
				LabeledContent
				{
					Slider(value:$strokeWidth,in:0.1...100)
				}
			label:
				{
					Text("Stroke \(strokeWidth)")
						.lineLimit(1)
						.frame(width: 120)
				}
			}
		}
    }
}



#Preview 
{
	@Previewable @State var spikeWidth = CGFloat(30)
	@Previewable @State var spikeHeight = CGFloat(30)
	@Previewable @State var strokeWidth = CGFloat(4)
	@Previewable @State var strokeColour = Color.black
	@Previewable @State var fillColour = Color.pink
	VStack
	{
		SpikyRectShape(spikeHeight: spikeHeight,spikeWidth: spikeWidth)
			.fill(fillColour)
			.stroke(strokeColour, lineWidth:strokeWidth)
			.padding(60)
		
		GroupBox("Params")
		{
			LabeledContent
			{
				Slider(value:$spikeWidth,in:0.1...100)
			}
			label:
			{
				Text("Spike Width \(spikeWidth)")
					.lineLimit(1)
					.frame(width: 120)
			}
			
			LabeledContent
			{
				Slider(value:$spikeHeight,in:0.1...100)
			}
		label:
			{
				Text("Spike Height \(spikeHeight)")
					.lineLimit(1)
					.frame(width: 120)
			}
			
			LabeledContent
			{
				Slider(value:$strokeWidth,in:0.1...100)
			}
			label:
			{
				Text("Stroke \(strokeWidth)")
					.lineLimit(1)
					.frame(width: 120)
			}
		}
	}
}
