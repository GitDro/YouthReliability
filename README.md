# Reliability of developmental MRI

Contains data and analysis towards:

> Drobinin, V., Gestel, H. V., Helmick, C. A., Schmidt, M. H., Bowen, C. V., & Uher, R. (2020). Reliability of multimodal MRI brain measures in youth at risk for mental illness. Brain and Behavior, e01609. https://doi.org/10.1002/brb3.1609

![Structural reliability](https://github.com/GitDro/YouthReliability/blob/master/figs/Fig%201.%20All%20GM.jpg)

## Getting started

#### To view the analysis:

1. Download the repository and extract.
2. Open `YouthReliability.nb.html` with any modern browser. This is the _knit_ or _rendered_ R notebook for quick and easy exploration with no installation requirements.

#### To run the analysis:

1. Download or clone the repository and extract.
2. Open the _R Project_ file `YouthReliability.Rproj`.
3. Open the _R Notebook_ if not already opened `YouthReliability.Rmd`
4. Click `Run All`


---

Note, running the notebook will check for required R packages and install them if missing. A minimum number of commonly used packages are required and they are summarized below.

```{r}
library(tidyverse) # ggplot, dplyr, tidyr, readr, purr, tibble
library(ICC) # ICC and CI
library(glue) # data into strings for in-text output
```

[![DOI](https://zenodo.org/badge/200237986.svg)](https://zenodo.org/badge/latestdoi/200237986)
