import           Control.Monad.IO.Class (liftIO)
import           Data.Array ((!))
import qualified Data.ByteString      as BS
import qualified Data.Conduit         as C
import           Data.Conduit.Binary (sinkHandle)
import qualified Data.Conduit.List    as CL
import qualified Data.Conduit.Text    as CT
import           Data.Text (pack, unpack)
import           Data.Time.Clock
import qualified Network.HTTP.Conduit as HC
import           System.IO
import           Text.Regex.Base.RegexLike
import           Text.Regex.Posix.String

header :: [String]
header = [ "{-# LANGUAGE OverloadedStrings #-}"
         , ""
         , "import           Data.Char"
         , "import           Data.Maybe"
         , "import           Data.Serialize.Get hiding (getTreeOf)"
         , "import           Data.Serialize.Put"
         , "import qualified Data.Text                              as T"
         , "import           Debug.Trace"
         , "import           Network.PublicSuffixList.DataStructure"
         , "import qualified Network.PublicSuffixList.Lookup        as L"
         , "import           Network.PublicSuffixList.Serialize"
         , "import           System.Exit"
         , "import           Test.HUnit"
         , "import           Text.IDNA"
         , ""
         , ""
         , "isSuffix' :: T.Text -> Bool"
         , "isSuffix' = L.isSuffix . T.intercalate \".\" . map (fromJust . toASCII False True . T.map toLower) . T.split (== '.')"
         ]

header2 :: [String]
header2 = [ "hunittests :: Test"
          , "hunittests = TestList ["
          ]

footer :: [String]
footer = [ "  ]"
         , ""
         , "testSerializationRoundTrip = TestCase $ assertEqual \"Round Trip\" dataStructure ds"
         , "  where Right ds = runGet getDataStructure serializedDataStructure"
         , "        serializedDataStructure = runPut $ putDataStructure dataStructure"
         , ""
         , "main = do"
         , "  counts <- runTestTT $ TestList [TestLabel \"Mozilla Tests\" hunittests, TestLabel \"Round Trip\" testSerializationRoundTrip]"
         , "  if errors counts == 0 && failures counts == 0"
         , "    then exitSuccess"
         , "    else exitFailure"
         ]

whitespace :: String -> Bool
whitespace = matchTest regex
  where regex = makeRegex "^[[:blank:]]*$" :: Regex

comment :: String -> Bool
comment = matchTest regex
  where regex = makeRegex "^[[:blank:]]*//" :: Regex

nullinput :: String -> Bool
nullinput = (==) "checkPublicSuffix(null, null);"

startswithdot :: String -> Bool
startswithdot = matchTest regex
  where regex = makeRegex "^checkPublicSuffix\\('\\.(.+)', (.+)\\);$" :: Regex

input :: String -> (String, Bool)
input s = (l, head r /= '\'')
  where regex = makeRegex "^checkPublicSuffix\\('(.+)', (.+)\\);$" :: Regex
        matches = head $ matchAllText regex s
        l = fst $ matches ! 1
        r = fst $ matches ! 2

counter :: (Monad m, Num t1) => C.Conduit t m (t, t1)
counter = counterHelper 0
  where counterHelper count = C.await >>= \ x -> case x of
          Nothing -> return ()
          Just a -> C.yield (a, count) >> counterHelper (count + 1)

intersperse :: (Monad m) => a -> C.Conduit a m a
intersperse i = C.await >>= \ x -> case x of
  Nothing -> return ()
  Just a -> C.yield a >> intersperseHelper
  where intersperseHelper = C.await >>= \ x -> case x of
          Nothing -> return ()
          Just a -> C.yield i >> C.yield a >> intersperseHelper

output :: Show t1 => ((String, Bool), t1) -> String
output ((s, b), c) = "  TestCase $ assertEqual \"" ++ (show c) ++ "\" " ++ (show b) ++ " $ isSuffix' \"" ++ s ++ "\""

populateFile :: String -> String -> IO ()
populateFile url filename = withFile filename WriteMode $ \ h -> do
  current_time <- getCurrentTime
  putStrLn $ "Fetched Public Suffix List at " ++ show current_time
  mapM_ (hPutStrLn h) header
  hPutStrLn h $ "-- DO NOT MODIFY! This file has been automatically generated from the Create.hs script at " ++ show current_time
  mapM_ (hPutStrLn h) header2
  req <- HC.parseUrl url
  HC.withManager $ \ manager -> do
    res <- HC.http req manager
    HC.responseBody res C.$$+-
      CT.decode CT.utf8 C.=$
      CT.lines C.=$
      CL.map unpack C.=$
      CL.filter (not . whitespace) C.=$
      CL.filter (not . comment) C.=$
      CL.filter (not . nullinput) C.=$
      CL.filter (not . startswithdot) C.=$
      CL.map input C.=$
      counter C.=$
      CL.map output C.=$
      intersperse ",\n" C.=$
      CL.map pack C.=$
      CT.encode CT.utf8 C.=$
      sinkHandle h
  mapM_ (hPutStrLn h) footer

main :: IO ()
main = populateFile "http://mxr.mozilla.org/mozilla-central/source/netwerk/test/unit/data/test_psl.txt?raw=1" "Test/PublicSuffixList.hs"
