#!/usr/bin/env python3
import os
import json

import csv
from colorama import Fore, Back, Style
import semtk3

import multiprocessing

import os
import os.path
DEBUG = False
def Debug(*args):
    if DEBUG:
        print(*args)


######################################
# 0.0 == confirmedDifferent
# 0.0 < assumedDifferent <= 0.5
# 0.5 < possibleSameAs <= 0.9
# 0.8 < assumedSameAs < 1.0
# 1.0 == confirmedSameAs    
######################################

reportString = """{} / {} - {}
  Best Match:{}
  Score:{}{}{}
------------------------------------------------------------------------"""

class ResolutionEngine:
    entityList = None
    ruleList = None
    resolutions = None
    processed = 0
    sourceConnection = None
    resolvedConnection = None
    logString = ""
    
    def __init__(self, copy=True):
        self.entityList = list()
        self.ruleList = list()
        self.sourceConnection = """
{   "name":"RACK local fuseki Apache Phase 2",
    "domain":"",
    "enableOwlImports":false,
    "model":[
        {"type":"fuseki","url":"http://localhost:3030/RACK","graph":"http://rack001/model"}
        ],
    "data":[
        {"type":"fuseki","url":"http://localhost:3030/RACK","graph":"http://rack001/data"}
        ]
}"""
        self.resolvedConnection = """
{   "name":"RACK local fuseki Apache Phase 2 Resolved",
    "domain":"",
    "enableOwlImports":false,
    "model":[
        {"type":"fuseki","url":"http://localhost:3030/RACK","graph":"http://rack001/model"}
        ],
    "data":[
        {"type":"fuseki","url":"http://localhost:3030/RACK","graph":"http://rack001/ResolvedData"}
        ]
}"""
        semtk3.set_connection_override(self.resolvedConnection)
        all_ok = semtk3.check_services();
        if not all_ok: 
            raise Exception("Semtk services are not properly running on localhost")
        if copy:
            self.copyGraph()
      
    def __runRules__(self, eP, eS):
        Score = 1
        for ruleType, rule in self.ruleList:
            applicable, level = rule(eP, eS)
            if applicable:
                if ruleType == "Absolute":
                    return level
                else:
                    Score += level
        return Score
        
    def addEntities(self, entityUriList):
        self.entityList = entityUriList
    
    def addAbsoluteRule(self, ruleFunction):
        self.ruleList.append(["Absolute", ruleFunction])
    
    def addRelativeRule(self, ruleFunction):
        self.ruleList.append(["Relative", ruleFunction])

    def work(self, eP):
        maxScore = 0
        bestMatch = None
        resolutions = {}
        Score = 0.0
        for eS in self.entityList[eP]:
            Score = self.__runRules__(eP,eS)
            resolutions[eS] = Score
            if Score > maxScore:
                maxScore = Score
                bestMatch = eS
        color = Fore.WHITE
        if Score> 2:
            color = Fore.YELLOW
        elif Score > 4:
            color = Fore.GREEN

        with open("Resolutions/"+eP.split("#")[-1]+".json", "w") as out:
            json.dump(resolutions, out, indent=4)
            
        with open("Resolutions/Summary.csv", "a") as out:
            out.write("{},{},{}\n".format(eP,bestMatch ,maxScore))
            
        print(reportString.format(len(os.listdir("Resolutions")), len(self.entityList), eP, bestMatch, color,str(maxScore),Style.RESET_ALL))

    def runAllAnalysis(self):
        
        ######################################################################
        print("Intializing Resolution Dictionary..")
        for f in os.listdir("Resolutions"):
            os.remove(os.path.join("Resolutions",f))
        with open("Resolutions/Summary.csv", "w") as out:
            out.write("Primary,Best Match,Score\n")
        print("  Initialization Done.")
        ######################################################################
        
        ######################################################################
        print("Running Analysis..")
        #for k in self.entityList.keys():
        #    self.work(k)
        with multiprocessing.Pool() as pool:
            pool.map(self.work, self.entityList.keys())
        print("  Analysis Complete.")
        ######################################################################
        

    def copyGraph(self):
        print("Copying Data Graph...")
        
        Debug("   downloading data...")
        semtk3.download_owl("Model.owl", self.sourceConnection, model_or_data=semtk3.SEMTK3_CONN_DATA, conn_index = 0)   
        
        Debug("   clearing resolved graph...")
        semtk3.clear_graph(self.resolvedConnection, model_or_data=semtk3.SEMTK3_CONN_DATA, index=0)
        
        Debug("   loading data to resolved graph...")

        semtk3.upload_owl("Model.owl", self.resolvedConnection, model_or_data=semtk3.SEMTK3_CONN_DATA, conn_index = 0)
        Debug("  Data Graph Copied.")
    
    
    def updateRACK(self):
        for r in self.resolutions:
            if self.resolutions[r] >= 1.0:
                semtk.combine_entities(r[0],r[1])
                
        pass
                    
                        
                        
                
    
