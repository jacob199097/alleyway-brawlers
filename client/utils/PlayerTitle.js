const TITLES = [
    { minLevel:  1, title: 'Street Prospect'   },
    { minLevel:  5, title: 'Alley Runner'       },
    { minLevel: 10, title: 'Corner Hustler'     },
    { minLevel: 15, title: 'Turf Brawler'       },
    { minLevel: 20, title: 'Made Enforcer'      },
    { minLevel: 25, title: 'Shot Caller'        },
    { minLevel: 30, title: 'District Fixer'     },
    { minLevel: 35, title: 'Crew Chief'         },
    { minLevel: 40, title: 'Underboss'          },
    { minLevel: 45, title: 'Syndicate Kingpin'  },
    { minLevel: 50, title: 'King of the Streets'},
];

/**
 * Returns the title for a given player level (1–50).
 * @param {number} level
 * @returns {string}
 */
export function getPlayerTitle(level) {
    let title = TITLES[0].title;
    for (const entry of TITLES) {
        if (level >= entry.minLevel) title = entry.title;
        else break;
    }
    return title;
}
