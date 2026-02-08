import { ThemedView } from '@/components/themed-view'
import * as ScreenOrientation from 'expo-screen-orientation'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
    Animated,
    StyleSheet,
    Text,
    TouchableOpacity,
    useWindowDimensions,
    View
} from 'react-native'
import {
    Camera,
    useCameraDevice,
    useCameraFormat,
    useCameraPermission,
    useFrameProcessor,
    VisionCameraProxy
} from 'react-native-vision-camera'
import { Worklets } from 'react-native-worklets-core'
  
type DribbleState = {
  lastY: number | null
  minY: number | null
  maxY: number | null
  lastDir: Direction
  lastCountTs: number
  count: number
  pendingBounce: boolean 
}

type Direction = 'down' | 'up' | null

const DribbleDrill: React.FC = () => {
  
  const [dribbleCount, setDribbleCount] = useState(0)
  const [ballPosition, setBallPosition] = useState<{ x: number; y: number } | null>(null)
  const [timeRemaining, setTimeRemaining] = useState<number | null>(null)
  const [ready, setReady] = useState(false)
  const [countdownTimer, setCountdownTimer] = useState(3)
  const readyTimerOpacity = useRef(new Animated.Value(1)).current
  const camera = useRef(null)
  const dribbleState = useRef<DribbleState>({
    lastY: null,
    minY: null,
    maxY: null,
    lastDir: null,
    lastCountTs: 0,
    count: 0,
    pendingBounce: false,
  })
  const { width, height } = useWindowDimensions()
  const { hasPermission, requestPermission } = useCameraPermission()
  const device = useCameraDevice('back')
  const format = useCameraFormat(device, [{ photoResolution: 'max' }])
  const detectBall = useMemo(() => VisionCameraProxy.initFrameProcessorPlugin('detectBall', {}), [])
useEffect(() => {
    ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.LANDSCAPE_LEFT)
}, [])

  useEffect(() => {
    if (!hasPermission) {
      requestPermission()
    }
  }, [hasPermission, requestPermission])

  useEffect(() => {
    if (!ready) return

    if (countdownTimer <= 0) {
      Animated.timing(readyTimerOpacity, {
        toValue: 0,
        duration: 0,
        useNativeDriver: true,
      }).start(() => {
        setReady(false)
        setTimeRemaining(60)
        setDribbleCount(0)
        readyTimerOpacity.setValue(1)
      })
      return
    }

    const interval = setInterval(() => {
      setCountdownTimer(prev => prev - 1)
    }, 1000)

    return () => clearInterval(interval)
  }, [countdownTimer, ready])

  useEffect(() => {
    if (!timeRemaining && !ready) return

    const interval = setInterval(() => {
      setTimeRemaining(prev => (prev ? prev - 1 : null))
    }, 1000)

    return () => clearInterval(interval)
  }, [timeRemaining])

  const onBall = useCallback(
    (res: any) => {
      if (timeRemaining === null) return

      const det = res?.detections?.[0]
      if (!det || det.confidence < 0.7) {
        setBallPosition(null)
        return
      }

      setBallPosition({ x: det.centerX, y: det.centerY })
      const ts = Date.now()
      const currentPos = det.centerX
      const s = dribbleState.current
      if (s.lastY == null) {
        s.lastY = currentPos
        s.minY = currentPos
        s.maxY = currentPos
        return
      }

      const delta = currentPos - s.lastY
      const DEADZONE = 0.02
      const MIN_AMPLITUDE = 0.08
      const MIN_DOWN_TRAVEL = 0.05
      const BOUNCE_COOLDOWN = 400
      const dir: Direction = Math.abs(delta) < DEADZONE ? null : delta < 0 ? 'down' : 'up'

      if (dir === 'down') {
        if (s.minY === null || currentPos < s.minY) {
          s.minY = currentPos
        }
        if (s.maxY !== null && s.maxY - currentPos >= MIN_DOWN_TRAVEL) {
          s.pendingBounce = true
        }
      }

      if (dir === 'up') {
        if (s.maxY === null || currentPos > s.maxY) {
          s.maxY = currentPos
        }
      }

      if (dir === 'up' && s.lastDir === 'down' && s.pendingBounce) {
        const amplitude = s.minY !== null && s.maxY !== null ? Math.abs(s.maxY - s.minY) : 0

        if (ts - s.lastCountTs > BOUNCE_COOLDOWN && amplitude >= MIN_AMPLITUDE) {
          s.count += 1
          s.lastCountTs = ts
          setDribbleCount(s.count)

          s.minY = currentPos
          s.maxY = currentPos
          s.pendingBounce = false
        }
      }

      if (dir === 'down' && s.lastDir === 'up') {
        s.maxY = s.lastY
        s.minY = currentPos
        s.pendingBounce = false
      }

      if (dir) s.lastDir = dir
      s.lastY = currentPos
    },
    [timeRemaining]
  )

  const onBallJS = useMemo(() => Worklets.createRunOnJS(onBall), [onBall])

  const startDrill = useCallback(() => {
    setReady(true)
    setCountdownTimer(3)
  }, [setReady, setCountdownTimer])

  const endDrill = useCallback(() => {
    setReady(false)
    setTimeRemaining(null)
    setDribbleCount(0)
    setBallPosition(null)
    setCountdownTimer(3)
    dribbleState.current = {
      lastY: null,
      minY: null,
      maxY: null,
      lastDir: null,
      lastCountTs: 0,
      count: 0,
      pendingBounce: false,
    }
  }, [])

  const frameProcessor = useFrameProcessor(
    frame => {
      'worklet'

      try {
        const res = detectBall?.call(frame)
        if (res) {
          onBallJS(res)
        }
      } catch (e: any) {
        console.error(e)
      }
    },
    [detectBall, onBallJS]
  )

  if (!device) {
    return (
      <ThemedView style={styles.container}>
        <Text>No device</Text>
      </ThemedView>
    )
  }

  return (
    <ThemedView style={styles.container}>
      <Camera
        device={device}
        isActive={true}
        ref={camera}
        format={format}
        frameProcessor={frameProcessor}
        style={StyleSheet.absoluteFill}
        fps={25}
        outputOrientation="device"
      />   
      {/* Countdown Timer Section */}
      {ready && countdownTimer > 0 && (
        <Animated.View style={[styles.readyTimer, { opacity: readyTimerOpacity }]}>
          <Text style={styles.readyTimerText}>{countdownTimer}</Text>
        </Animated.View>
      )}

      {!ready && !timeRemaining && (
        <Animated.View style={[styles.startButton, { opacity: readyTimerOpacity }]}>
          <TouchableOpacity onPress={startDrill}>
            <Text style={styles.startButtonText}>Start</Text>
          </TouchableOpacity>
        </Animated.View>
      )}
      {timeRemaining !== null && timeRemaining > 0 && (
        <>
          <View style={styles.counter}>
            <Text style={styles.counterText}>{dribbleCount}</Text>
          </View>
          {ballPosition && (
            <View
              style={[
                styles.ballDot,
                {
                  left: ballPosition.y * width - 75,
                  top: (1 - ballPosition.x) * height - 10,
                },
              ]}
            />
          )}
          <View style={styles.timer}>
            <Text style={styles.timerText}>{timeRemaining}</Text>
          </View>
          <TouchableOpacity style={styles.endButton} onPress={endDrill}>
            <Text style={styles.endButtonText}>End</Text>
          </TouchableOpacity>
        </>
      )}
    </ThemedView>
  )
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: 'red',
    alignItems: 'center',
    justifyContent: 'center',
  },
  counter: {
    backgroundColor: 'rgba(0,0,0,0.5)',
    padding: 10,
    borderRadius: 10,
    position: 'absolute',
    top: 50,
    left: 20,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 10,
    zIndex: 1000,
  },
  counterText: {
    color: 'white',
    fontSize: 30,
    fontWeight: 'bold',
  },
  ballDot: {
    width: 20,
    height: 20,
    backgroundColor: 'red',
    borderRadius: 10,
    position: 'absolute',
    zIndex: 1000,
  },
  timer: {
    backgroundColor: 'rgba(0,0,0,0.5)',
    padding: 10,
    borderRadius: 10,
    position: 'absolute',
    top: 50,
    right: 20,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 10,
    zIndex: 1000,
  },
  timerText: {
    color: 'white',
    fontSize: 30,
    fontWeight: 'bold',
  },
  startButton: {
    backgroundColor: 'green',
    position: 'absolute',
    bottom: 50,
    left: '50%',
    transform: [{ translateX: -100 }],
    marginBottom: 10,
    zIndex: 1000,
    padding: 5,
    borderRadius: 50,
    width: 200,
    height: 75,
    alignItems: 'center',
    justifyContent: 'center',
  },
  startButtonText: {
    color: '#fff',
    fontSize: 24,
    fontWeight: 'bold',
  },
  endButton: {
    backgroundColor: 'red',
    position: 'absolute',
    bottom: 25,
    right: 20,
    marginBottom: 10,
    zIndex: 1000,
    padding: 5,
    borderRadius: 50,
    width: 75,
    height: 75,
    alignItems: 'center',
    justifyContent: 'center',
  },
  endButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  readyTimer: {
    backgroundColor: 'rgba(0,0,0,0.5)',
    padding: 10,
    borderRadius: 10,
    position: 'absolute',
    left: '50%',
    top: '50%',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 10,
    zIndex: 1000,
  },
  readyTimerText: {
    color: 'white',
    fontSize: 50,
    fontWeight: 'bold',
  },
})

export default DribbleDrill
